// SPDX-License-Identifier: MIT
pragma solidity 0.8.37;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ForwarderFactory} from "../src/ForwarderFactory.sol";
import {Forwarder} from "../src/Forwarder.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {MockNoReturnERC20} from "./mocks/MockNoReturnERC20.sol";
import {RejectingReceiver} from "./mocks/RejectingReceiver.sol";
import {ReentrantReceiver} from "./mocks/ReentrantReceiver.sol";
import {MockBlockingERC20} from "./mocks/MockBlockingERC20.sol";

contract ForwarderFactoryTest is Test {
    uint16 internal constant MAX_FEE_BPS = 200;
    uint16 internal constant FEE_BPS = 50;

    ForwarderFactory internal factory;
    MockERC20 internal usdc;
    MockERC20 internal bscUsd;

    address internal feeRecipient = makeAddr("feeRecipient");
    address internal merchant = makeAddr("merchant");
    address internal payer = makeAddr("payer");
    address internal stranger = makeAddr("stranger");
    bytes32 internal salt = keccak256("invoice-1");

    event ForwarderDeployed(
        bytes32 indexed invoiceSalt, address indexed forwarder, address indexed merchant, uint16 feeBps
    );
    event Flushed(
        address indexed token,
        address indexed merchant,
        address indexed feeRecipient,
        uint256 merchantAmount,
        uint256 feeAmount
    );

    function setUp() public {
        factory = new ForwarderFactory(feeRecipient, MAX_FEE_BPS);
        usdc = new MockERC20("USD Coin", "USDC", 6);
        bscUsd = new MockERC20("Binance-Peg USD", "USD", 18);
    }

    // ---------------------------------------------------------------- constructor

    function test_constructor_setsImmutables() public view {
        assertEq(factory.feeRecipient(), feeRecipient);
        assertEq(factory.maxFeeBps(), MAX_FEE_BPS);
        assertTrue(factory.implementation().code.length > 0);
        assertEq(Forwarder(payable(factory.implementation())).factory(), address(factory));
    }

    function test_constructor_revertsOnZeroFeeRecipient() public {
        vm.expectRevert(ForwarderFactory.ZeroAddress.selector);
        new ForwarderFactory(address(0), MAX_FEE_BPS);
    }

    function test_constructor_revertsOnCapAboveDenominator() public {
        vm.expectRevert(abi.encodeWithSelector(ForwarderFactory.CapAboveDenominator.selector, uint16(10_001)));
        new ForwarderFactory(feeRecipient, 10_001);
    }

    function test_constructor_allowsCapEqualToDenominator() public {
        ForwarderFactory f = new ForwarderFactory(feeRecipient, 10_000);
        assertEq(f.maxFeeBps(), 10_000);
    }

    // ---------------------------------------------------------------- computeAddress

    function test_computeAddress_matchesDeployedForwarder() public {
        address predicted = factory.computeAddress(salt, merchant, FEE_BPS);
        usdc.mint(predicted, 1_000e6);
        address deployed = factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));
        assertEq(deployed, predicted);
    }

    function test_computeAddress_hasNoCodeBeforeSweep() public view {
        assertEq(factory.computeAddress(salt, merchant, FEE_BPS).code.length, 0);
    }

    function test_computeAddress_bindsMerchant() public {
        assertTrue(factory.computeAddress(salt, merchant, FEE_BPS) != factory.computeAddress(salt, stranger, FEE_BPS));
    }

    function test_computeAddress_bindsFee() public view {
        assertTrue(factory.computeAddress(salt, merchant, FEE_BPS) != factory.computeAddress(salt, merchant, 0));
    }

    function test_computeAddress_bindsSalt() public view {
        assertTrue(
            factory.computeAddress(salt, merchant, FEE_BPS)
                != factory.computeAddress(keccak256("invoice-2"), merchant, FEE_BPS)
        );
    }

    function test_computeAddress_revertsOnZeroMerchant() public {
        vm.expectRevert(ForwarderFactory.ZeroAddress.selector);
        factory.computeAddress(salt, address(0), FEE_BPS);
    }

    function test_computeAddress_revertsOnFeeAboveCap() public {
        vm.expectRevert(abi.encodeWithSelector(ForwarderFactory.FeeAboveCap.selector, uint16(201), MAX_FEE_BPS));
        factory.computeAddress(salt, merchant, 201);
    }

    // ---------------------------------------------------------------- sweep (ERC-20)

    function test_sweep_splitsFeeAndForwardsRest() public {
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        usdc.mint(deposit, 100e6);

        factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));

        assertEq(usdc.balanceOf(feeRecipient), 0.5e6);
        assertEq(usdc.balanceOf(merchant), 99.5e6);
        assertEq(usdc.balanceOf(deposit), 0);
    }

    function test_sweep_worksWith18DecimalToken() public {
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        bscUsd.mint(deposit, 100e18);

        factory.sweep(salt, merchant, FEE_BPS, IERC20(address(bscUsd)));

        assertEq(bscUsd.balanceOf(feeRecipient), 0.5e18);
        assertEq(bscUsd.balanceOf(merchant), 99.5e18);
    }

    function test_sweep_zeroFeeSendsEverythingToMerchant() public {
        address deposit = factory.computeAddress(salt, merchant, 0);
        usdc.mint(deposit, 42e6);

        factory.sweep(salt, merchant, 0, IERC20(address(usdc)));

        assertEq(usdc.balanceOf(merchant), 42e6);
        assertEq(usdc.balanceOf(feeRecipient), 0);
    }

    function test_sweep_feeRoundsDownInMerchantsFavour() public {
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        usdc.mint(deposit, 199); // 199 * 50 / 10000 = 0.995 -> 0

        factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));

        assertEq(usdc.balanceOf(feeRecipient), 0);
        assertEq(usdc.balanceOf(merchant), 199);
    }

    function test_sweep_emitsDeployedAndFlushedEvents() public {
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        usdc.mint(deposit, 100e6);

        vm.expectEmit(true, true, true, true, address(factory));
        emit ForwarderDeployed(salt, deposit, merchant, FEE_BPS);
        vm.expectEmit(true, true, true, true, deposit);
        emit Flushed(address(usdc), merchant, feeRecipient, 99.5e6, 0.5e6);

        factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));
    }

    function test_sweep_secondSweepReusesForwarderAndCatchesLatePayment() public {
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        usdc.mint(deposit, 10e6);
        factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));

        usdc.mint(deposit, 20e6);
        vm.recordLogs();
        address again = factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));

        assertEq(again, deposit);
        assertEq(usdc.balanceOf(merchant), 29.85e6);
        assertEq(usdc.balanceOf(feeRecipient), 0.15e6);
        // No second ForwarderDeployed event.
        assertEq(vm.getRecordedLogs().length, 3); // fee Transfer, merchant Transfer, Flushed
    }

    function test_sweep_zeroBalanceIsNoOp() public {
        address deposit = factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));
        assertTrue(deposit.code.length > 0);
        assertEq(usdc.balanceOf(merchant), 0);
    }

    function test_sweep_isPermissionless() public {
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        usdc.mint(deposit, 100e6);

        vm.prank(stranger);
        factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));

        assertEq(usdc.balanceOf(merchant), 99.5e6);
        assertEq(usdc.balanceOf(stranger), 0);
    }

    function test_sweep_wrongMerchantCannotReachFunds() public {
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        usdc.mint(deposit, 100e6);

        // Same salt with another merchant resolves to a different (empty) address.
        address other = factory.sweep(salt, stranger, FEE_BPS, IERC20(address(usdc)));

        assertTrue(other != deposit);
        assertEq(usdc.balanceOf(stranger), 0);
        assertEq(usdc.balanceOf(deposit), 100e6);
    }

    function test_sweep_wrongFeeCannotReachFunds() public {
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        usdc.mint(deposit, 100e6);

        factory.sweep(salt, merchant, MAX_FEE_BPS, IERC20(address(usdc)));

        assertEq(usdc.balanceOf(deposit), 100e6);
        assertEq(usdc.balanceOf(feeRecipient), 0);
    }

    function test_sweep_supportsTokenWithoutReturnValue() public {
        MockNoReturnERC20 usdt = new MockNoReturnERC20();
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        usdt.mint(deposit, 100e6);

        factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdt)));

        assertEq(usdt.balanceOf(merchant), 99.5e6);
        assertEq(usdt.balanceOf(feeRecipient), 0.5e6);
    }

    function test_sweep_revertsOnZeroMerchant() public {
        vm.expectRevert(ForwarderFactory.ZeroAddress.selector);
        factory.sweep(salt, address(0), FEE_BPS, IERC20(address(usdc)));
    }

    function test_sweep_revertsOnFeeAboveCap() public {
        vm.expectRevert(abi.encodeWithSelector(ForwarderFactory.FeeAboveCap.selector, uint16(201), MAX_FEE_BPS));
        factory.sweep(salt, merchant, 201, IERC20(address(usdc)));
    }

    // ---------------------------------------------------------------- sweepNative

    function test_sweepNative_splitsNativeCoin() public {
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        vm.deal(payer, 1 ether);
        vm.prank(payer);
        (bool ok,) = deposit.call{value: 1 ether}("");
        assertTrue(ok);

        factory.sweepNative(salt, merchant, FEE_BPS);

        assertEq(feeRecipient.balance, 0.005 ether);
        assertEq(merchant.balance, 0.995 ether);
        assertEq(deposit.balance, 0);
    }

    function test_sweepNative_zeroFeeSkipsFeeTransfer() public {
        address deposit = factory.computeAddress(salt, merchant, 0);
        vm.deal(deposit, 1 ether);

        factory.sweepNative(salt, merchant, 0);

        assertEq(merchant.balance, 1 ether);
        assertEq(feeRecipient.balance, 0);
    }

    function test_sweepNative_zeroBalanceIsNoOp() public {
        factory.sweepNative(salt, merchant, FEE_BPS);
        assertEq(merchant.balance, 0);
    }

    function test_sweepNative_revertsWhenMerchantRejects() public {
        RejectingReceiver rejecting = new RejectingReceiver();
        address deposit = factory.computeAddress(salt, address(rejecting), FEE_BPS);
        vm.deal(deposit, 1 ether);

        vm.expectRevert(abi.encodeWithSelector(Forwarder.NativeTransferFailed.selector, address(rejecting)));
        factory.sweepNative(salt, address(rejecting), FEE_BPS);
    }

    // ---------------------------------------------------------------- a blocked fee recipient never blocks merchants

    function test_sweep_feeRecipientBlockedByIssuer_paysMerchantEverything() public {
        MockBlockingERC20 token = new MockBlockingERC20();
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        token.mint(deposit, 1_000_000);
        token.block_(feeRecipient);

        vm.expectEmit(true, true, true, true);
        emit Flushed(address(token), merchant, feeRecipient, 1_000_000, 0);
        factory.sweep(salt, merchant, FEE_BPS, IERC20(address(token)));

        assertEq(token.balanceOf(merchant), 1_000_000);
        assertEq(token.balanceOf(feeRecipient), 0);
        assertEq(token.balanceOf(deposit), 0);
    }

    function test_sweep_merchantBlockedByIssuer_revertsAndKeepsEverything() public {
        MockBlockingERC20 token = new MockBlockingERC20();
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        token.mint(deposit, 1_000_000);
        token.block_(merchant);

        vm.expectRevert(abi.encodeWithSelector(MockBlockingERC20.Blocked.selector, merchant));
        factory.sweep(salt, merchant, FEE_BPS, IERC20(address(token)));

        assertEq(token.balanceOf(deposit), 1_000_000);
        assertEq(token.balanceOf(feeRecipient), 0);
    }

    function test_sweepNative_feeRecipientRejecting_paysMerchantEverything() public {
        ForwarderFactory rejectingFeeFactory = new ForwarderFactory(address(new RejectingReceiver()), MAX_FEE_BPS);
        address deposit = rejectingFeeFactory.computeAddress(salt, merchant, FEE_BPS);
        vm.deal(deposit, 1 ether);

        vm.expectEmit(true, true, true, true);
        emit Flushed(address(0), merchant, rejectingFeeFactory.feeRecipient(), 1 ether, 0);
        rejectingFeeFactory.sweepNative(salt, merchant, FEE_BPS);

        assertEq(merchant.balance, 1 ether);
        assertEq(deposit.balance, 0);
    }

    function test_sweep_normalPathStillTakesTheFee() public {
        MockBlockingERC20 token = new MockBlockingERC20();
        address deposit = factory.computeAddress(salt, merchant, FEE_BPS);
        token.mint(deposit, 1_000_000);

        factory.sweep(salt, merchant, FEE_BPS, IERC20(address(token)));

        assertEq(token.balanceOf(feeRecipient), 5_000);
        assertEq(token.balanceOf(merchant), 995_000);
    }

    function test_sweepNative_reentrancyCannotOverpay() public {
        ReentrantReceiver reentrant = new ReentrantReceiver();
        address deposit = factory.computeAddress(salt, address(reentrant), FEE_BPS);
        vm.deal(deposit, 1 ether);
        // Deploy first so the receiver can target the forwarder.
        factory.sweep(salt, address(reentrant), FEE_BPS, IERC20(address(usdc)));
        reentrant.setTarget(Forwarder(payable(deposit)));

        factory.sweepNative(salt, address(reentrant), FEE_BPS);

        assertEq(reentrant.reentries(), 1);
        assertEq(address(reentrant).balance + feeRecipient.balance, 1 ether);
        assertEq(feeRecipient.balance, 0.005 ether);
    }

    // ---------------------------------------------------------------- forwarder access control

    function test_forwarder_initializeOnlyByFactory() public {
        address deposit = factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));
        vm.prank(stranger);
        vm.expectRevert(Forwarder.NotFactory.selector);
        Forwarder(payable(deposit)).initialize(stranger, 0);
    }

    function test_forwarder_cannotBeReinitializedByFactory() public {
        address deposit = factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));
        vm.prank(address(factory));
        vm.expectRevert(Forwarder.AlreadyInitialized.selector);
        Forwarder(payable(deposit)).initialize(stranger, 0);
    }

    function test_forwarder_storesBinding() public {
        address deposit = factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));
        assertEq(Forwarder(payable(deposit)).merchant(), merchant);
        assertEq(Forwarder(payable(deposit)).feeBps(), FEE_BPS);
        assertEq(Forwarder(payable(deposit)).factory(), address(factory));
    }

    function test_forwarder_directFlushByAnyoneGoesToMerchant() public {
        address deposit = factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));
        usdc.mint(deposit, 100e6);

        vm.prank(stranger);
        Forwarder(payable(deposit)).flush(IERC20(address(usdc)));

        assertEq(usdc.balanceOf(merchant), 99.5e6);
        assertEq(usdc.balanceOf(feeRecipient), 0.5e6);
    }

    function test_forwarder_rejectsZeroMerchantEvenFromFactory() public {
        Forwarder impl = Forwarder(payable(factory.implementation()));
        vm.prank(address(factory));
        vm.expectRevert(Forwarder.ZeroMerchant.selector);
        impl.initialize(address(0), 0);
    }

    function test_forwarder_acceptsNativeAfterDeployment() public {
        address deposit = factory.sweep(salt, merchant, FEE_BPS, IERC20(address(usdc)));
        vm.deal(payer, 1 ether);
        vm.prank(payer);
        (bool ok,) = deposit.call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(deposit.balance, 1 ether);

        Forwarder(payable(deposit)).flushNative();
        assertEq(merchant.balance, 0.995 ether);
    }

    function test_implementation_cannotBeInitializedByAnyone() public {
        Forwarder impl = Forwarder(payable(factory.implementation()));
        vm.prank(stranger);
        vm.expectRevert(Forwarder.NotFactory.selector);
        impl.initialize(stranger, 0);
    }

    function test_implementation_flushRevertsUninitialized() public {
        Forwarder impl = Forwarder(payable(factory.implementation()));
        usdc.mint(address(impl), 1e6);
        vm.expectRevert(Forwarder.NotInitialized.selector);
        impl.flush(IERC20(address(usdc)));
    }

    function test_implementation_flushNativeRevertsUninitialized() public {
        Forwarder impl = Forwarder(payable(factory.implementation()));
        vm.expectRevert(Forwarder.NotInitialized.selector);
        impl.flushNative();
    }

    // ---------------------------------------------------------------- fuzz

    function testFuzz_sweep_partsAlwaysSumToBalance(bytes32 invoiceSalt, uint16 feeBps, uint128 amount) public {
        feeBps = uint16(bound(feeBps, 0, MAX_FEE_BPS));
        address m = makeAddr("fuzzMerchant");
        address deposit = factory.computeAddress(invoiceSalt, m, feeBps);
        usdc.mint(deposit, amount);

        factory.sweep(invoiceSalt, m, feeBps, IERC20(address(usdc)));

        uint256 fee = usdc.balanceOf(feeRecipient);
        assertEq(fee + usdc.balanceOf(m), amount);
        assertEq(fee, (uint256(amount) * feeBps) / 10_000);
        assertLe(fee * 10_000, uint256(amount) * MAX_FEE_BPS);
        assertEq(usdc.balanceOf(deposit), 0);
    }

    function testFuzz_computeAddress_isDeterministicAndUnique(bytes32 a, bytes32 b) public view {
        vm.assume(a != b);
        assertEq(factory.computeAddress(a, merchant, FEE_BPS), factory.computeAddress(a, merchant, FEE_BPS));
        assertTrue(factory.computeAddress(a, merchant, FEE_BPS) != factory.computeAddress(b, merchant, FEE_BPS));
    }

    function testFuzz_feeAboveCapAlwaysReverts(uint16 feeBps) public {
        feeBps = uint16(bound(feeBps, MAX_FEE_BPS + 1, type(uint16).max));
        vm.expectRevert(abi.encodeWithSelector(ForwarderFactory.FeeAboveCap.selector, feeBps, MAX_FEE_BPS));
        factory.sweep(salt, merchant, feeBps, IERC20(address(usdc)));
    }
}
