// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import {IHooks} from "v4-core/src/interfaces/IHooks.sol";
import {Hooks} from "v4-core/src/libraries/Hooks.sol";
import {TickMath} from "v4-core/src/libraries/TickMath.sol";
import {IPoolManager} from "v4-core/src/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/src/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/src/types/BalanceDelta.sol";
import {PoolId, PoolIdLibrary} from "v4-core/src/types/PoolId.sol";
import {CurrencyLibrary, Currency} from "v4-core/src/types/Currency.sol";
import {PoolSwapTest} from "v4-core/src/test/PoolSwapTest.sol";
import {MainHook} from "../src/MainHook.sol";
import {StateLibrary} from "v4-core/src/libraries/StateLibrary.sol";
import {IIdentitySBT} from "../src/interfaces/IIdentitySBT.sol";

import {LiquidityAmounts} from "v4-core/test/utils/LiquidityAmounts.sol";
import {IPositionManager} from "v4-periphery/src/interfaces/IPositionManager.sol";
import {EasyPosm} from "./utils/EasyPosm.sol";
import {Fixtures} from "./utils/Fixtures.sol";
import {KYCContract} from "../src/KYCContract.sol";
import {MockIdentitySBT} from "../src/mock/MockIdentitySBT.sol";
import {MockOracle} from "../src/mock/MockOracle.sol";

contract MainHookTest is Test, Fixtures {
    using EasyPosm for IPositionManager;
    using PoolIdLibrary for PoolKey;
    using CurrencyLibrary for Currency;
    using StateLibrary for IPoolManager;

    MainHook hook;
    PoolId poolId;
    MockIdentitySBT identitySBT;
    KYCContract kycContract;
    MockOracle oracle;
    uint256 tokenId;
    int24 tickLower;
    int24 tickUpper;

    function setUp() public {
        // creates the pool manager, utility routers, and test tokens
        deployFreshManagerAndRouters();
        deployMintAndApprove2Currencies();

        deployAndApprovePosm(manager);

        // Deploy mock IdentitySBT
        identitySBT = new MockIdentitySBT();
        identitySBT.setKYC(tx.origin, true);

        // Deploy kyc contract
        kycContract = new KYCContract(address(identitySBT));

        // Set up price feeds for the actual tokens used in the pool
        oracle = new MockOracle();
        kycContract.setPriceFeed(Currency.unwrap(currency0), address(oracle));
        kycContract.setPriceFeed(Currency.unwrap(currency1), address(oracle));
        oracle.setPrice(1);

        // Deploy the hook to an address with the correct flags
        address flags = address(
            uint160(
                Hooks.BEFORE_SWAP_FLAG | Hooks.BEFORE_ADD_LIQUIDITY_FLAG | Hooks.BEFORE_REMOVE_LIQUIDITY_FLAG
            ) ^ (0x4444 << 144) // Namespace the hook to avoid collisions
        );
        bytes memory constructorArgs = abi.encode(manager, address(kycContract));
        deployCodeTo("MainHook.sol:MainHook", constructorArgs, flags);
        hook = MainHook(flags);

        // Create the pool
        key = PoolKey(currency0, currency1, 3000, 60, IHooks(hook));
        poolId = key.toId();
        manager.initialize(key, SQRT_PRICE_1_1);

        // Provide full-range liquidity to the pool
        tickLower = TickMath.minUsableTick(key.tickSpacing);
        tickUpper = TickMath.maxUsableTick(key.tickSpacing);

        uint128 liquidityAmount = 1000;

        (uint256 amount0Expected, uint256 amount1Expected) = LiquidityAmounts.getAmountsForLiquidity(
            SQRT_PRICE_1_1,
            TickMath.getSqrtPriceAtTick(tickLower),
            TickMath.getSqrtPriceAtTick(tickUpper),
            liquidityAmount
        );


        (tokenId,) = posm.mint(
            key,
            tickLower,
            tickUpper,
            liquidityAmount,
            amount0Expected + 1,
            amount1Expected + 1,
            address(this),
            block.timestamp,
            ZERO_BYTES
        );
    }

    function testSwapWithKYC_LowVolume() public {
        // Test swap with KYC'ed user
        bool zeroForOne = true;
        int256 amountSpecified = -500e18;
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        assertEq(int256(swapDelta.amount0()), amountSpecified);
    }

    function testSwapWithKYC_HighVolume() public {
        oracle.setPrice(5001);

        // Test swap with KYC'ed user
        bool zeroForOne = true;
        int256 amountSpecified = -2e18;
        vm.expectRevert();
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
    }

    function testSwapWithKYC() public {

        oracle.setPrice(500);

        // Test swap with KYC'ed user
        bool zeroForOne = true;
        int256 amountSpecified = -2e18;
        BalanceDelta swapDelta = swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
        assertEq(int256(swapDelta.amount0()), amountSpecified);
    }

    function testSwapWithoutKYC() public {
        // Revoke KYC
        identitySBT.setKYC(tx.origin, false);

        bool zeroForOne = true;
        int256 amountSpecified = -1000e18;
        vm.expectRevert();
        swap(key, zeroForOne, amountSpecified, ZERO_BYTES);
    }

} 