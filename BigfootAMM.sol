// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ✅ IMPORTS COMPLETS POUR REMIX
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/token/ERC20/IERC20.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/security/ReentrancyGuard.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/security/Pausable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/access/Ownable.sol";
import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/v4.9.3/contracts/utils/math/Math.sol";

interface IBigfootVault {
    function depositYield(uint256 amount) external;
}

/**
 * @title BigfootAMM
 * @dev AMM sécurisé et complet pour l'écosystème BFT Lab - Version Remix
 * @notice Gère deux pools: BFT/WPOL et BFT/USDC
 */
contract BigfootAMM is ReentrancyGuard, Pausable, Ownable {
    
    /* ========== CONSTANTES ========== */
    
    uint256 private constant FEE_DENOMINATOR = 10000;
    uint256 public constant SWAP_FEE = 30;      // 0.3%
    uint256 public constant PROTOCOL_FEE = 10;  // 0.1%
    uint256 public constant MAX_SLIPPAGE_BPS = 500; // 5%
    
    /* ========== IMMUTABLES ========== */
    
    IERC20 public immutable bftToken;
    IERC20 public immutable usdcToken;
    IERC20 public immutable wpolToken;
    IBigfootVault public immutable vault;
    
    uint8 public immutable bftDecimals;
    uint8 public immutable usdcDecimals;
    uint8 public immutable wpolDecimals;
    
    /* ========== STATE VARIABLES ========== */
    
    // Pool BFT/WPOL
    uint256 public reserveBFTWPOL;
    uint256 public reserveWPOLBFT;
    uint256 public totalLpBftWpol;
    mapping(address => uint256) public lpBalancesBftWpol;
    
    // Pool BFT/USDC
    uint256 public reserveBFTUSDC;
    uint256 public reserveUSDCBFT;
    uint256 public totalLpBftUsdc;
    mapping(address => uint256) public lpBalancesBftUsdc;
    
    // Sécurité
    mapping(address => uint256) private _lastOperationBlock;
    uint256 public maxSwapAmount = type(uint256).max;
    uint256 public minLiquidityAmount = 10**6; // Adapté à USDC (6 decimals)
    
    /* ========== EVENTS ========== */
    
    event LiquidityAdded(
        address indexed provider,
        string pair,
        uint256 amountA,
        uint256 amountB,
        uint256 lpShares,
        uint256 timestamp
    );
    
    event LiquidityRemoved(
        address indexed provider,
        string pair,
        uint256 amountA,
        uint256 amountB,
        uint256 lpShares,
        uint256 timestamp
    );
    
    event SwapExecuted(
        address indexed user,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 fee,
        uint256 protocolFee,
        uint256 timestamp
    );
    
    event SafetyLimitsUpdated(string limitName, uint256 newValue);
    event EmergencyWithdrawal(address indexed token, uint256 amount);
    
    /* ========== MODIFIERS ========== */
    
    modifier validPair(address tokenA, address tokenB) {
        require(
            (tokenA == address(bftToken) && tokenB == address(wpolToken)) ||
            (tokenA == address(wpolToken) && tokenB == address(bftToken)) ||
            (tokenA == address(bftToken) && tokenB == address(usdcToken)) ||
            (tokenA == address(usdcToken) && tokenB == address(bftToken)),
            "Invalid pair"
        );
        _;
    }
    
    modifier nonZeroAmount(uint256 amount) {
        require(amount > 0, "Amount must be > 0");
        _;
    }
    
    modifier antiFrontRun() {
        require(
            _lastOperationBlock[msg.sender] < block.number,
            "Front-running protection: one operation per block"
        );
        _;
    }
    
    /* ========== CONSTRUCTOR ========== */
    
    constructor(
        address _bftToken,
        address _usdcToken,
        address _wpolToken,
        address _vault
    ) {
        require(_bftToken != address(0), "BFT token zero address");
        require(_usdcToken != address(0), "USDC token zero address");
        require(_wpolToken != address(0), "WPOL token zero address");
        require(_vault != address(0), "Vault zero address");
        
        bftToken = IERC20(_bftToken);
        usdcToken = IERC20(_usdcToken);
        wpolToken = IERC20(_wpolToken);
        vault = IBigfootVault(_vault);
        
        bftDecimals = IERC20Metadata(_bftToken).decimals();
        usdcDecimals = IERC20Metadata(_usdcToken).decimals();
        wpolDecimals = IERC20Metadata(_wpolToken).decimals();
        
        _transferOwnership(msg.sender);
    }
    
    /* ========== LIQUIDITY MANAGEMENT (BFT/WPOL) ========== */
    
    function addLiquidityBFTWPOL(
        uint256 amountBFTDesired,
        uint256 amountWPOLDesired,
        uint256 amountBFTMin,
        uint256 amountWPOLMin
    ) 
        external 
        nonReentrant 
        whenNotPaused 
        nonZeroAmount(amountBFTDesired)
        nonZeroAmount(amountWPOLDesired)
        antiFrontRun 
        returns (uint256 amountBFT, uint256 amountWPOL, uint256 lpShares) 
    {
        require(amountBFTDesired >= amountBFTMin, "BFT amount below minimum");
        require(amountWPOLDesired >= amountWPOLMin, "WPOL amount below minimum");
        
        (amountBFT, amountWPOL) = _calculateOptimalAmounts(
            amountBFTDesired,
            amountWPOLDesired,
            reserveBFTWPOL,
            reserveWPOLBFT
        );
        
        require(amountBFT >= minLiquidityAmount, "BFT amount too low");
        require(amountWPOL >= minLiquidityAmount, "WPOL amount too low");
        
        if (totalLpBftWpol == 0) {
            lpShares = Math.sqrt(amountBFT * amountWPOL);
            require(lpShares >= 1000, "Initial liquidity too low");
        } else {
            lpShares = Math.min(
                (amountBFT * totalLpBftWpol) / reserveBFTWPOL,
                (amountWPOL * totalLpBftWpol) / reserveWPOLBFT
            );
        }
        
        require(lpShares > 0, "No LP shares minted");
        
        _safeTransferFrom(address(bftToken), msg.sender, address(this), amountBFT);
        _safeTransferFrom(address(wpolToken), msg.sender, address(this), amountWPOL);
        
        reserveBFTWPOL += amountBFT;
        reserveWPOLBFT += amountWPOL;
        totalLpBftWpol += lpShares;
        lpBalancesBftWpol[msg.sender] += lpShares;
        
        _lastOperationBlock[msg.sender] = block.number;
        
        emit LiquidityAdded(
            msg.sender, 
            "BFT/WPOL", 
            amountBFT, 
            amountWPOL, 
            lpShares, 
            block.timestamp
        );
        
        return (amountBFT, amountWPOL, lpShares);
    }
    
    function removeLiquidityBFTWPOL(
        uint256 lpShares,
        uint256 amountBFTMin,
        uint256 amountWPOLMin
    ) 
        external 
        nonReentrant 
        whenNotPaused 
        nonZeroAmount(lpShares)
        antiFrontRun 
        returns (uint256 amountBFT, uint256 amountWPOL) 
    {
        require(lpBalancesBftWpol[msg.sender] >= lpShares, "Insufficient LP balance");
        require(totalLpBftWpol > 0, "No liquidity to remove");
        
        amountBFT = (lpShares * reserveBFTWPOL) / totalLpBftWpol;
        amountWPOL = (lpShares * reserveWPOLBFT) / totalLpBftWpol;
        
        require(amountBFT >= amountBFTMin, "BFT amount below minimum");
        require(amountWPOL >= amountWPOLMin, "WPOL amount below minimum");
        require(amountBFT > 0 && amountWPOL > 0, "Amounts must be > 0");
        
        lpBalancesBftWpol[msg.sender] -= lpShares;
        totalLpBftWpol -= lpShares;
        reserveBFTWPOL -= amountBFT;
        reserveWPOLBFT -= amountWPOL;
        
        _safeTransfer(address(bftToken), msg.sender, amountBFT);
        _safeTransfer(address(wpolToken), msg.sender, amountWPOL);
        
        _lastOperationBlock[msg.sender] = block.number;
        
        emit LiquidityRemoved(
            msg.sender, 
            "BFT/WPOL", 
            amountBFT, 
            amountWPOL, 
            lpShares, 
            block.timestamp
        );
        
        return (amountBFT, amountWPOL);
    }

    /* ========== LIQUIDITY MANAGEMENT (BFT/USDC) ========== */
    
    function addLiquidityBFTUSDC(
        uint256 amountBFTDesired,
        uint256 amountUSDCDesired,
        uint256 amountBFTMin,
        uint256 amountUSDCMin
    ) 
        external 
        nonReentrant 
        whenNotPaused 
        nonZeroAmount(amountBFTDesired)
        nonZeroAmount(amountUSDCDesired)
        antiFrontRun 
        returns (uint256 amountBFT, uint256 amountUSDC, uint256 lpShares) 
    {
        require(amountBFTDesired >= amountBFTMin, "BFT amount below minimum");
        require(amountUSDCDesired >= amountUSDCMin, "USDC amount below minimum");
        
        (amountBFT, amountUSDC) = _calculateOptimalAmounts(
            amountBFTDesired,
            amountUSDCDesired,
            reserveBFTUSDC,
            reserveUSDCBFT
        );
        
        require(amountBFT >= minLiquidityAmount, "BFT amount too low");
        require(amountUSDC >= minLiquidityAmount, "USDC amount too low");
        
        if (totalLpBftUsdc == 0) {
            lpShares = Math.sqrt(amountBFT * amountUSDC);
            require(lpShares >= 1000, "Initial liquidity too low");
        } else {
            lpShares = Math.min(
                (amountBFT * totalLpBftUsdc) / reserveBFTUSDC,
                (amountUSDC * totalLpBftUsdc) / reserveUSDCBFT
            );
        }
        
        require(lpShares > 0, "No LP shares minted");
        
        _safeTransferFrom(address(bftToken), msg.sender, address(this), amountBFT);
        _safeTransferFrom(address(usdcToken), msg.sender, address(this), amountUSDC);
        
        reserveBFTUSDC += amountBFT;
        reserveUSDCBFT += amountUSDC;
        totalLpBftUsdc += lpShares;
        lpBalancesBftUsdc[msg.sender] += lpShares;
        
        _lastOperationBlock[msg.sender] = block.number;
        
        emit LiquidityAdded(
            msg.sender, 
            "BFT/USDC", 
            amountBFT, 
            amountUSDC, 
            lpShares, 
            block.timestamp
        );
        
        return (amountBFT, amountUSDC, lpShares);
    }
    
    function removeLiquidityBFTUSDC(
        uint256 lpShares,
        uint256 amountBFTMin,
        uint256 amountUSDCMin
    ) 
        external 
        nonReentrant 
        whenNotPaused 
        nonZeroAmount(lpShares)
        antiFrontRun 
        returns (uint256 amountBFT, uint256 amountUSDC) 
    {
        require(lpBalancesBftUsdc[msg.sender] >= lpShares, "Insufficient LP balance");
        require(totalLpBftUsdc > 0, "No liquidity to remove");
        
        amountBFT = (lpShares * reserveBFTUSDC) / totalLpBftUsdc;
        amountUSDC = (lpShares * reserveUSDCBFT) / totalLpBftUsdc;
        
        require(amountBFT >= amountBFTMin, "BFT amount below minimum");
        require(amountUSDC >= amountUSDCMin, "USDC amount below minimum");
        require(amountBFT > 0 && amountUSDC > 0, "Amounts must be > 0");
        
        lpBalancesBftUsdc[msg.sender] -= lpShares;
        totalLpBftUsdc -= lpShares;
        reserveBFTUSDC -= amountBFT;
        reserveUSDCBFT -= amountUSDC;
        
        _safeTransfer(address(bftToken), msg.sender, amountBFT);
        _safeTransfer(address(usdcToken), msg.sender, amountUSDC);
        
        _lastOperationBlock[msg.sender] = block.number;
        
        emit LiquidityRemoved(
            msg.sender, 
            "BFT/USDC", 
            amountBFT, 
            amountUSDC, 
            lpShares, 
            block.timestamp
        );
        
        return (amountBFT, amountUSDC);
    }

    /* ========== SWAP FUNCTIONS (BFT/WPOL) ========== */
    
    function swapWPOLForBFT(
        uint256 amountWPOLIn,
        uint256 amountBFTOutMin
    ) 
        external 
        nonReentrant 
        whenNotPaused 
        nonZeroAmount(amountWPOLIn)
        antiFrontRun 
        returns (uint256 amountBFTOut) 
    {
        require(amountWPOLIn <= maxSwapAmount, "Amount exceeds max swap limit");
        
        // ✅ CORRECTION: Déclaration séparée des variables
        uint256 fee;
        uint256 protocolFee;
        (amountBFTOut, fee, protocolFee) = _calculateSwapOutput(
            amountWPOLIn,
            reserveWPOLBFT,
            reserveBFTWPOL
        );
        
        require(amountBFTOut >= amountBFTOutMin, "Slippage limits exceeded");
        require(amountBFTOut > 0, "Output amount too low");
        _validateSlippage(amountBFTOut, amountBFTOutMin);
        
        _safeTransferFrom(address(wpolToken), msg.sender, address(this), amountWPOLIn);
        
        if (protocolFee > 0) {
            _safeTransfer(address(wpolToken), address(vault), protocolFee);
            try vault.depositYield(protocolFee) {} catch {
                // Silently fail - fees stay in contract
            }
        }
        
        _safeTransfer(address(bftToken), msg.sender, amountBFTOut);
        
        reserveWPOLBFT += amountWPOLIn;
        reserveBFTWPOL -= amountBFTOut;
        
        _lastOperationBlock[msg.sender] = block.number;
        
        emit SwapExecuted(
            msg.sender, 
            address(wpolToken), 
            address(bftToken), 
            amountWPOLIn, 
            amountBFTOut, 
            fee, 
            protocolFee, 
            block.timestamp
        );
        
        return amountBFTOut;
    }
    
    function swapBFTForWPOL(
        uint256 amountBFTIn,
        uint256 amountWPOLOutMin
    ) 
        external 
        nonReentrant 
        whenNotPaused 
        nonZeroAmount(amountBFTIn)
        antiFrontRun 
        returns (uint256 amountWPOLOut) 
    {
        require(amountBFTIn <= maxSwapAmount, "Amount exceeds max swap limit");
        
        // ✅ CORRECTION: Déclaration séparée des variables
        uint256 fee;
        uint256 protocolFee;
        (amountWPOLOut, fee, protocolFee) = _calculateSwapOutput(
            amountBFTIn,
            reserveBFTWPOL,
            reserveWPOLBFT
        );
        
        require(amountWPOLOut >= amountWPOLOutMin, "Slippage limits exceeded");
        require(amountWPOLOut > 0, "Output amount too low");
        _validateSlippage(amountWPOLOut, amountWPOLOutMin);
        
        _safeTransferFrom(address(bftToken), msg.sender, address(this), amountBFTIn);
        
        if (protocolFee > 0) {
            _safeApprove(address(bftToken), address(vault), protocolFee);
            try vault.depositYield(protocolFee) {} catch {
                // Silently fail - fees stay in contract
            }
        }
        
        _safeTransfer(address(wpolToken), msg.sender, amountWPOLOut);
        
        reserveBFTWPOL += amountBFTIn;
        reserveWPOLBFT -= amountWPOLOut;
        
        _lastOperationBlock[msg.sender] = block.number;
        
        emit SwapExecuted(
            msg.sender, 
            address(bftToken), 
            address(wpolToken), 
            amountBFTIn, 
            amountWPOLOut, 
            fee, 
            protocolFee, 
            block.timestamp
        );
        
        return amountWPOLOut;
    }

    /* ========== SWAP FUNCTIONS (BFT/USDC) ========== */
    
    function swapUSDCForBFT(
        uint256 amountUSDCIn,
        uint256 amountBFTOutMin
    ) 
        external 
        nonReentrant 
        whenNotPaused 
        nonZeroAmount(amountUSDCIn)
        antiFrontRun 
        returns (uint256 amountBFTOut) 
    {
        require(amountUSDCIn <= maxSwapAmount, "Amount exceeds max swap limit");
        
        // ✅ CORRECTION: Déclaration séparée des variables
        uint256 fee;
        uint256 protocolFee;
        (amountBFTOut, fee, protocolFee) = _calculateSwapOutput(
            amountUSDCIn,
            reserveUSDCBFT,
            reserveBFTUSDC
        );
        
        require(amountBFTOut >= amountBFTOutMin, "Slippage limits exceeded");
        require(amountBFTOut > 0, "Output amount too low");
        _validateSlippage(amountBFTOut, amountBFTOutMin);
        
        _safeTransferFrom(address(usdcToken), msg.sender, address(this), amountUSDCIn);
        
        if (protocolFee > 0) {
            _safeTransfer(address(usdcToken), address(vault), protocolFee);
            try vault.depositYield(protocolFee) {} catch {
                // Silently fail - fees stay in contract
            }
        }
        
        _safeTransfer(address(bftToken), msg.sender, amountBFTOut);
        
        reserveUSDCBFT += amountUSDCIn;
        reserveBFTUSDC -= amountBFTOut;
        
        _lastOperationBlock[msg.sender] = block.number;
        
        emit SwapExecuted(
            msg.sender, 
            address(usdcToken), 
            address(bftToken), 
            amountUSDCIn, 
            amountBFTOut, 
            fee, 
            protocolFee, 
            block.timestamp
        );
        
        return amountBFTOut;
    }
    
    function swapBFTForUSDC(
        uint256 amountBFTIn,
        uint256 amountUSDCOutMin
    ) 
        external 
        nonReentrant 
        whenNotPaused 
        nonZeroAmount(amountBFTIn)
        antiFrontRun 
        returns (uint256 amountUSDCOut) 
    {
        require(amountBFTIn <= maxSwapAmount, "Amount exceeds max swap limit");
        
        // ✅ CORRECTION: Déclaration séparée des variables
        uint256 fee;
        uint256 protocolFee;
        (amountUSDCOut, fee, protocolFee) = _calculateSwapOutput(
            amountBFTIn,
            reserveBFTUSDC,
            reserveUSDCBFT
        );
        
        require(amountUSDCOut >= amountUSDCOutMin, "Slippage limits exceeded");
        require(amountUSDCOut > 0, "Output amount too low");
        _validateSlippage(amountUSDCOut, amountUSDCOutMin);
        
        _safeTransferFrom(address(bftToken), msg.sender, address(this), amountBFTIn);
        
        if (protocolFee > 0) {
            _safeApprove(address(bftToken), address(vault), protocolFee);
            try vault.depositYield(protocolFee) {} catch {
                // Silently fail - fees stay in contract
            }
        }
        
        _safeTransfer(address(usdcToken), msg.sender, amountUSDCOut);
        
        reserveBFTUSDC += amountBFTIn;
        reserveUSDCBFT -= amountUSDCOut;
        
        _lastOperationBlock[msg.sender] = block.number;
        
        emit SwapExecuted(
            msg.sender, 
            address(bftToken), 
            address(usdcToken), 
            amountBFTIn, 
            amountUSDCOut, 
            fee, 
            protocolFee, 
            block.timestamp
        );
        
        return amountUSDCOut;
    }

    /* ========== VIEW FUNCTIONS ========== */
    
    function getAmountOut(
        address tokenIn,
        address tokenOut,
        uint256 amountIn
    ) 
        public 
        view 
        validPair(tokenIn, tokenOut) 
        returns (uint256 amountOut) 
    {
        require(amountIn > 0, "Amount must be > 0");
        
        (uint256 reserveIn, uint256 reserveOut) = _getReserves(tokenIn, tokenOut);
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - SWAP_FEE);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        
        return numerator / denominator;
    }
    
    function getReserves(address tokenA, address tokenB) 
        external 
        view 
        validPair(tokenA, tokenB) 
        returns (uint256 reserveA, uint256 reserveB) 
    {
        (reserveA, reserveB) = _getReserves(tokenA, tokenB);
        return (reserveA, reserveB);
    }
    
    function getLpBalance(address user, string memory pair) 
        external 
        view 
        returns (uint256) 
    {
        if (keccak256(bytes(pair)) == keccak256(bytes("BFT/WPOL"))) {
            return lpBalancesBftWpol[user];
        } else if (keccak256(bytes(pair)) == keccak256(bytes("BFT/USDC"))) {
            return lpBalancesBftUsdc[user];
        }
        return 0;
    }
    
    function getLpTotalSupply(string memory pair) 
        external 
        view 
        returns (uint256) 
    {
        if (keccak256(bytes(pair)) == keccak256(bytes("BFT/WPOL"))) {
            return totalLpBftWpol;
        } else if (keccak256(bytes(pair)) == keccak256(bytes("BFT/USDC"))) {
            return totalLpBftUsdc;
        }
        return 0;
    }

    /* ========== INTERNAL FUNCTIONS ========== */
    
    function _calculateOptimalAmounts(
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 reserveA,
        uint256 reserveB
    ) 
        private 
        pure 
        returns (uint256 amountA, uint256 amountB) 
    {
        if (reserveA == 0 && reserveB == 0) {
            return (amountADesired, amountBDesired);
        }
        
        uint256 amountBOptimal = (amountADesired * reserveB) / reserveA;
        if (amountBOptimal <= amountBDesired) {
            return (amountADesired, amountBOptimal);
        } else {
            uint256 amountAOptimal = (amountBDesired * reserveA) / reserveB;
            return (amountAOptimal, amountBDesired);
        }
    }
    
    function _calculateSwapOutput(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) 
        private 
        pure 
        returns (uint256 amountOut, uint256 fee, uint256 protocolFee) 
    {
        require(reserveIn > 0 && reserveOut > 0, "Insufficient liquidity");
        
        uint256 amountInWithFee = amountIn * (FEE_DENOMINATOR - SWAP_FEE);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = (reserveIn * FEE_DENOMINATOR) + amountInWithFee;
        
        amountOut = numerator / denominator;
        fee = (amountIn * SWAP_FEE) / FEE_DENOMINATOR;
        protocolFee = (fee * PROTOCOL_FEE) / SWAP_FEE;
        
        if (protocolFee > fee) {
            protocolFee = fee;
        }
        
        return (amountOut, fee, protocolFee);
    }
    
    function _getReserves(address tokenA, address tokenB) 
        private 
        view 
        returns (uint256 reserveA, uint256 reserveB) 
    {
        if (tokenA == address(bftToken) && tokenB == address(wpolToken)) {
            return (reserveBFTWPOL, reserveWPOLBFT);
        } else if (tokenA == address(wpolToken) && tokenB == address(bftToken)) {
            return (reserveWPOLBFT, reserveBFTWPOL);
        } else if (tokenA == address(bftToken) && tokenB == address(usdcToken)) {
            return (reserveBFTUSDC, reserveUSDCBFT);
        } else if (tokenA == address(usdcToken) && tokenB == address(bftToken)) {
            return (reserveUSDCBFT, reserveBFTUSDC);
        }
        revert("Invalid pair");
    }
    
    function _validateSlippage(uint256 amountOut, uint256 amountOutMin) private pure {
        if (amountOutMin > 0) {
            uint256 slippageBps = ((amountOut - amountOutMin) * 10000) / amountOut;
            require(slippageBps <= MAX_SLIPPAGE_BPS, "Slippage too high");
        }
    }
    
    /* ========== SECURE TOKEN TRANSFERS ========== */
    
    function _safeTransfer(address token, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transfer.selector, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Transfer failed");
    }
    
    function _safeTransferFrom(address token, address from, address to, uint256 amount) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.transferFrom.selector, from, to, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "TransferFrom failed");
    }
    
    function _safeApprove(address token, address spender, uint256 amount) private {
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(IERC20.approve.selector, spender, amount)
        );
        require(success && (data.length == 0 || abi.decode(data, (bool))), "Approve failed");
    }
    
    /* ========== ADMIN FUNCTIONS ========== */
    
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function setMaxSwapAmount(uint256 _maxSwapAmount) external onlyOwner {
        require(_maxSwapAmount > 0, "Max swap amount must be > 0");
        maxSwapAmount = _maxSwapAmount;
        emit SafetyLimitsUpdated("maxSwapAmount", _maxSwapAmount);
    }
    
    function setMinLiquidityAmount(uint256 _minLiquidityAmount) external onlyOwner {
        require(_minLiquidityAmount > 0, "Min liquidity must be > 0");
        minLiquidityAmount = _minLiquidityAmount;
        emit SafetyLimitsUpdated("minLiquidityAmount", _minLiquidityAmount);
    }
    
    function emergencyWithdraw(address token, uint256 amount) external onlyOwner whenPaused {
        require(token != address(0), "Zero address");
        _safeTransfer(token, msg.sender, amount);
        emit EmergencyWithdrawal(token, amount);
    }
    
    function recoverTokens(address token, uint256 amount) external onlyOwner {
        require(token != address(bftToken), "Cannot recover BFT");
        require(token != address(wpolToken), "Cannot recover WPOL");
        require(token != address(usdcToken), "Cannot recover USDC");
        _safeTransfer(token, msg.sender, amount);
        emit EmergencyWithdrawal(token, amount);
    }
}
