// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";

import {ImmutableState} from "v4-periphery/src/base/ImmutableState.sol";
import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";

/// @title JIT
/// @notice A minimal contract for Just-In-Time (JIT) positions
abstract contract JIT is ImmutableState {
    using StateLibrary for IPoolManager;

    bytes32 constant TICK_LOWER_SLOT = keccak256("tickLower");
    bytes32 constant TICK_UPPER_SLOT = keccak256("tickUpper");

    constructor(IPoolManager _manager) ImmutableState(_manager) {}

    /// @notice Determine the tick range for the JIT position
    /// @param key The pool key
    /// @param params The IPoolManager.SwapParams of the current swap. Includes trade size and direction
    /// @param amount0 the currency0 amount to be used on the JIT range
    /// @param amount1 the currency1 amount to be used on the JIT range
    /// @param sqrtPriceX96 The current sqrt price of the pool
    /// @return tickLower The lower tick of the JIT position
    /// @return tickUpper The upper tick of the JIT position
    function _getTickRange(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        uint128 amount0,
        uint128 amount1,
        uint160 sqrtPriceX96
    ) internal view virtual returns (int24 tickLower, int24 tickUpper);

    /// @notice Create a JIT position
    /// @param key The pool key the position will be created on
    /// @param params The IPoolManager.SwapParams of the current swap
    /// @param amount0 the currency0 amount to be used on the JIT range
    /// @param amount1 the currency1 amount to be used on the JIT range
    function _createPosition(
        PoolKey calldata key,
        IPoolManager.SwapParams calldata params,
        uint128 amount0,
        uint128 amount1,
        bytes calldata hookDataOpen
    ) internal virtual returns (BalanceDelta delta, BalanceDelta feesAccrued, uint128 liquidity) {
        // fetch the tick range for the JIT position
        (uint160 sqrtPriceX96,,,) = poolManager.getSlot0(key.toId());
        (int24 tickLower, int24 tickUpper) = _getTickRange(key, params, amount0, amount1, sqrtPriceX96);

        // compute the liquidity units for the JIT position, with the given amounts
        liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            amount0,
            amount1
        );

        // store ticks to close the position, useful for calling _closePosition in a different function context
        _storeTicks(tickLower, tickUpper);

        // create the JIT position
        (delta, feesAccrued) = _modifyLiquidity(key, tickLower, tickUpper, int256(uint256(liquidity)), hookDataOpen);
    }

    /// @notice Close the JIT position
    /// @param key The pool key the position will be closed on
    /// @param liquidityToClose The amount of liquidity to close
    function _closePosition(PoolKey calldata key, uint128 liquidityToClose, bytes calldata hookDataClose)
        internal
        virtual
        returns (BalanceDelta delta, BalanceDelta feesAccrued)
    {
        // load the tick range of the JIT position
        (int24 tickLower, int24 tickUpper) = _loadTicks();

        // close the JIT position
        (delta, feesAccrued) =
            _modifyLiquidity(key, tickLower, tickUpper, -int256(uint256(liquidityToClose)), hookDataClose);
    }

    /// @notice Optionally overridable function for modifying liquidity on the core PoolManager
    /// @param key The pool key the position will be created on
    /// @param tickLower The lower tick of the JIT position
    /// @param tickUpper The upper tick of the JIT position
    /// @param liquidityDelta The amount of liquidity units to add or remove
    function _modifyLiquidity(
        PoolKey memory key,
        int24 tickLower,
        int24 tickUpper,
        int256 liquidityDelta,
        bytes calldata hookData
    ) internal virtual returns (BalanceDelta totalDelta, BalanceDelta feesAccrued) {
        (totalDelta, feesAccrued) = poolManager.modifyLiquidity(
            key,
            IPoolManager.ModifyLiquidityParams({
                tickLower: tickLower,
                tickUpper: tickUpper,
                liquidityDelta: liquidityDelta,
                salt: bytes32(0)
            }),
            hookData
        );
    }

    /// @dev Store the tick range of the JIT position
    function _storeTicks(int24 tickLower, int24 tickUpper) private {
        bytes32 tickLowerSlot = TICK_LOWER_SLOT;
        bytes32 tickUpperSlot = TICK_UPPER_SLOT;
        assembly {
            tstore(tickLowerSlot, tickLower)
            tstore(tickUpperSlot, tickUpper)
        }
    }

    /// @dev Load the tick range of the JIT position, to be used to close the position
    function _loadTicks() private view returns (int24 tickLower, int24 tickUpper) {
        bytes32 tickLowerSlot = TICK_LOWER_SLOT;
        bytes32 tickUpperSlot = TICK_UPPER_SLOT;
        assembly {
            tickLower := tload(tickLowerSlot)
            tickUpper := tload(tickUpperSlot)
        }
    }
}
