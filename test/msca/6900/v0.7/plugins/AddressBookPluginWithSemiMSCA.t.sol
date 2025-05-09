/*
 * Copyright 2024 Circle Internet Group, Inc. All rights reserved.

 * SPDX-License-Identifier: GPL-3.0-or-later

 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.

 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.

 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */
pragma solidity 0.8.24;

import {NotImplemented} from "../../../../../src/msca/6900/shared/common/Errors.sol";
import "../../../../../src/msca/6900/v0.7/account/semi/SingleOwnerMSCA.sol";
import "../../../../../src/msca/6900/v0.7/common/Structs.sol";
import "../../../../../src/msca/6900/v0.7/factories/semi/SingleOwnerMSCAFactory.sol";
import "../../../../../src/msca/6900/v0.7/interfaces/IPluginManager.sol";
import "../../../../../src/msca/6900/v0.7/interfaces/IStandardExecutor.sol";
import "../../../../../src/msca/6900/v0.7/libs/FunctionReferenceLib.sol";
import "../../../../../src/msca/6900/v0.7/plugins/v1_0_0/addressbook/AddressBookPlugin.sol";
import "../../../../../src/msca/6900/v0.7/plugins/v1_0_0/addressbook/IAddressBookPlugin.sol";
import "../../../../../src/utils/ExecutionUtils.sol";
import "../../../../util/TestLiquidityPool.sol";
import "../../../../util/TestUtils.sol";
import {EntryPoint} from "@account-abstraction/contracts/core/EntryPoint.sol";
import "forge-std/src/console.sol";

contract AddressBookPluginWithSemiMSCATest is TestUtils {
    using FunctionReferenceLib for bytes21;
    using FunctionReferenceLib for FunctionReference;
    using ExecutionUtils for address;
    // upgrade

    event Upgraded(address indexed newImplementation);
    // 4337
    event UserOperationEvent(
        bytes32 indexed userOpHash,
        address indexed sender,
        address indexed paymaster,
        uint256 nonce,
        bool success,
        uint256 actualGasCost,
        uint256 actualGasUsed
    );

    IEntryPoint private entryPoint = new EntryPoint();
    PluginManager private pluginManager = new PluginManager();
    uint256 internal eoaPrivateKey;
    address private ownerAddr;
    address payable beneficiary; // e.g. bundler
    SingleOwnerMSCAFactory private factory;
    AddressBookPlugin private addressBookPlugin;
    SingleOwnerMSCA private msca;
    TestLiquidityPool private testLiquidityPool;
    address private addressBookPluginAddr;
    address private mscaAddr;
    bytes32 addressBookPluginManifest;

    function setUp() public {
        beneficiary = payable(address(makeAddr("bundler")));
        factory = new SingleOwnerMSCAFactory(address(entryPoint), address(pluginManager));
        addressBookPlugin = new AddressBookPlugin();

        (ownerAddr, eoaPrivateKey) = makeAddrAndKey("AddressBookPluginWithSemiMSCATest");
        console.logString("owner address");
        console.logAddress(ownerAddr);
        bytes32 salt = 0x0000000000000000000000000000000000000000000000000000000000000000;
        vm.startPrank(ownerAddr);
        msca = factory.createAccount(ownerAddr, salt, abi.encode(ownerAddr));
        // deployment was done
        assertTrue(address(msca).code.length != 0);
        vm.stopPrank();
        addressBookPluginAddr = address(addressBookPlugin);
        console.logString("address book plugin address:");
        console.logAddress(addressBookPluginAddr);
        mscaAddr = address(msca);
        console.logString("msca address:");
        console.logAddress(mscaAddr);
        addressBookPluginManifest = keccak256(abi.encode(addressBookPlugin.pluginManifest()));
        testLiquidityPool = new TestLiquidityPool("getrich", "$$$");
        console.logString("ERC20 contract address:");
        console.logAddress(address(testLiquidityPool));
    }

    function testPluginMetadataItself() public view {
        PluginMetadata memory pluginMetadata = addressBookPlugin.pluginMetadata();
        assertEq(pluginMetadata.name, "Address Book Plugin");
        assertEq(pluginMetadata.version, PLUGIN_VERSION_1);
        assertEq(pluginMetadata.author, PLUGIN_AUTHOR);
        assertEq(pluginMetadata.permissionDescriptors.length, 5);
        assertEq(
            pluginMetadata.permissionDescriptors[0].functionSelector, AddressBookPlugin.executeWithAddressBook.selector
        );
        assertEq(pluginMetadata.permissionDescriptors[0].permissionDescription, "AddressBookRead");

        assertEq(
            pluginMetadata.permissionDescriptors[1].functionSelector,
            AddressBookPlugin.executeBatchWithAddressBook.selector
        );
        assertEq(pluginMetadata.permissionDescriptors[1].permissionDescription, "AddressBookRead");

        assertEq(
            pluginMetadata.permissionDescriptors[2].functionSelector, IAddressBookPlugin.addAllowedRecipients.selector
        );
        assertEq(pluginMetadata.permissionDescriptors[2].permissionDescription, "AddressBookWrite");

        assertEq(
            pluginMetadata.permissionDescriptors[3].functionSelector,
            IAddressBookPlugin.removeAllowedRecipients.selector
        );
        assertEq(pluginMetadata.permissionDescriptors[3].permissionDescription, "AddressBookWrite");

        assertEq(
            pluginMetadata.permissionDescriptors[4].functionSelector, IAddressBookPlugin.getAllowedRecipients.selector
        );
        assertEq(pluginMetadata.permissionDescriptors[4].permissionDescription, "AddressBookRead");
    }

    function testInstallAndUninstallAddressBookPluginDetails() public {
        address[] memory recipients = new address[](1);
        recipients[0] = vm.addr(1);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        //
        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        // verify the plugin has been installed
        address[] memory installedPlugins = msca.getInstalledPlugins();
        assertEq(installedPlugins.length, 1);
        assertEq(installedPlugins[0], addressBookPluginAddr);
        // verify executionDetail
        //    address plugin; // plugin address that implements the execution function, for native functions, the value
        // is set to address(0)
        //    FunctionReference userOpValidationFunction;
        //    FunctionReference[] preUserOpValidationHooks;
        //    FunctionReference runtimeValidationFunction;
        //    FunctionReference[] preRuntimeValidationHooks;
        //    ExecutionHooks[] executionHooks;
        // addAllowedRecipients function
        ExecutionFunctionConfig memory executionDetail =
            msca.getExecutionFunctionConfig(addressBookPlugin.addAllowedRecipients.selector);
        assertEq(executionDetail.plugin, addressBookPluginAddr);
        // use native validation instead
        assertEq(
            executionDetail.userOpValidationFunction.pack(),
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER)).pack()
        );
        assertEq(
            executionDetail.runtimeValidationFunction.pack(),
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF)).pack(
            )
        );

        // removeAllowedRecipients
        executionDetail = msca.getExecutionFunctionConfig(addressBookPlugin.removeAllowedRecipients.selector);
        assertEq(executionDetail.plugin, addressBookPluginAddr);
        // use native validation instead
        assertEq(
            executionDetail.userOpValidationFunction.pack(),
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER)).pack()
        );
        assertEq(
            executionDetail.runtimeValidationFunction.pack(),
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF)).pack(
            )
        );

        // getAllowedRecipients
        executionDetail = msca.getExecutionFunctionConfig(addressBookPlugin.getAllowedRecipients.selector);
        assertEq(executionDetail.plugin, addressBookPluginAddr);
        // use native validation instead
        assertEq(
            executionDetail.userOpValidationFunction.pack(),
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER)).pack()
        );
        assertEq(
            executionDetail.runtimeValidationFunction.pack(),
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF)).pack(
            )
        );

        // executeWithAddressBook
        executionDetail = msca.getExecutionFunctionConfig(addressBookPlugin.executeWithAddressBook.selector);
        assertEq(executionDetail.plugin, addressBookPluginAddr);
        // use native validation instead
        assertEq(
            executionDetail.userOpValidationFunction.pack(),
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER)).pack()
        );
        assertEq(
            executionDetail.runtimeValidationFunction.pack(),
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF)).pack(
            )
        );

        // executeBatchWithAddressBook
        executionDetail = msca.getExecutionFunctionConfig(addressBookPlugin.executeBatchWithAddressBook.selector);
        assertEq(executionDetail.plugin, addressBookPluginAddr);
        // use native validation instead
        assertEq(
            executionDetail.userOpValidationFunction.pack(),
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER)).pack()
        );
        assertEq(
            executionDetail.runtimeValidationFunction.pack(),
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF)).pack(
            )
        );

        // execution hooks
        ExecutionHooks[] memory executionHooks = msca.getExecutionHooks(addressBookPlugin.addAllowedRecipients.selector);
        assertEq(executionHooks.length, 0);

        msca.getExecutionHooks(addressBookPlugin.removeAllowedRecipients.selector);
        assertEq(executionHooks.length, 0);

        msca.getExecutionHooks(addressBookPlugin.getAllowedRecipients.selector);
        assertEq(executionHooks.length, 0);

        // pre validation hooks
        (FunctionReference[] memory preUserOpValidationHooks, FunctionReference[] memory preRuntimeValidationHooks) =
            msca.getPreValidationHooks(AddressBookPlugin.executeWithAddressBook.selector);
        assertEq(preUserOpValidationHooks.length, 1);
        assertEq(
            preUserOpValidationHooks[0].pack(),
            FunctionReference(
                addressBookPluginAddr, uint8(AddressBookPlugin.FunctionId.PRE_USER_OP_VALIDATION_HOOK_ADDRESS_BOOK)
            ).pack()
        );
        assertEq(preRuntimeValidationHooks.length, 1);
        assertEq(
            preRuntimeValidationHooks[0].pack(),
            FunctionReference(
                addressBookPluginAddr, uint8(AddressBookPlugin.FunctionId.PRE_RUNTIME_VALIDATION_HOOK_ADDRESS_BOOK)
            ).pack()
        );

        (preUserOpValidationHooks, preRuntimeValidationHooks) =
            msca.getPreValidationHooks(IStandardExecutor.execute.selector);
        assertEq(preUserOpValidationHooks.length, 1);
        assertEq(preUserOpValidationHooks[0].pack(), PRE_HOOK_ALWAYS_DENY_FUNCTION_REFERENCE);
        assertEq(preRuntimeValidationHooks.length, 1);
        assertEq(preRuntimeValidationHooks[0].pack(), PRE_HOOK_ALWAYS_DENY_FUNCTION_REFERENCE);

        // uninstall it
        vm.startPrank(ownerAddr);
        msca.uninstallPlugin(addressBookPluginAddr, "", "");
        vm.stopPrank();
        assertEq(msca.getInstalledPlugins().length, 0);
        address[] memory allowedRecipients = addressBookPlugin.getAllowedRecipients(mscaAddr);
        assertEq(allowedRecipients.length, 0);
    }

    // run through hook (pass) => validation (pass)
    function testExecuteWithAddressBookPassPreUserOpHookAndValidation() public {
        // install plugin first
        address recipientAddr = vm.addr(1);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        address[] memory recipients = new address[](1);
        recipients[0] = recipientAddr;

        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        uint256 acctNonce = entryPoint.getNonce(mscaAddr, 0);
        bytes memory executeCallData =
            abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (recipientAddr, 1, "", recipientAddr));
        PackedUserOperation memory userOp = buildPartialUserOp(
            mscaAddr,
            acctNonce,
            "0x",
            vm.toString(executeCallData),
            83353,
            1028650,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        bytes memory signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        userOp.signature = signature;
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();
        // verify recipient balance
        assertEq(recipientAddr.balance, 1);
    }

    // run through hook (pass) => validation (fail)
    function testExecuteWithAddressBookPassPreUserOpHookButFailValidation() public {
        // install plugin first
        address recipientAddr = vm.addr(1);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        address[] memory recipients = new address[](1);
        recipients[0] = recipientAddr;

        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        uint256 acctNonce = entryPoint.getNonce(mscaAddr, 0);
        bytes memory executeCallData =
            abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (recipientAddr, 1, "", recipientAddr));
        PackedUserOperation memory userOp = buildPartialUserOp(
            mscaAddr,
            acctNonce,
            "0x",
            vm.toString(executeCallData),
            83353,
            1028650,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        (, uint256 randomPrivateKey) = makeAddrAndKey("testExecuteWithAddressBookPassPreUserOpHookButFailValidation");
        bytes memory signature = signUserOpHash(entryPoint, vm, randomPrivateKey, userOp);
        userOp.signature = signature;
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        vm.expectRevert();
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();
        // verify recipient balance
        assertEq(recipientAddr.balance, 0);
    }

    // run through hook (fail) => validation (pass)
    function testExecuteWithAddressBookFailPreUserOpHookButPassValidation() public {
        // install plugin first
        address recipientAddr = vm.addr(1);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        address[] memory recipients = new address[](0);

        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        uint256 acctNonce = entryPoint.getNonce(mscaAddr, 0);
        bytes memory executeCallData =
            abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (recipientAddr, 1, "", recipientAddr));
        PackedUserOperation memory userOp = buildPartialUserOp(
            mscaAddr,
            acctNonce,
            "0x",
            vm.toString(executeCallData),
            83353,
            1028650,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        bytes memory signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        userOp.signature = signature;
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        vm.expectRevert();
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();
        // verify recipient balance
        assertEq(recipientAddr.balance, 0);
    }

    // run through hook (fail) => validation (fail)
    function testExecuteWithAddressBookFailPreUserOpHookAndValidation() public {
        // install plugin first
        address recipientAddr = vm.addr(1);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        address[] memory recipients = new address[](0);

        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        uint256 acctNonce = entryPoint.getNonce(mscaAddr, 0);
        bytes memory executeCallData =
            abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (recipientAddr, 1, "", recipientAddr));
        PackedUserOperation memory userOp = buildPartialUserOp(
            mscaAddr,
            acctNonce,
            "0x",
            vm.toString(executeCallData),
            83353,
            1028650,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        (, uint256 randomPrivateKey) = makeAddrAndKey("testExecuteWithAddressBookFailPreUserOpHookAndValidation");
        bytes memory signature = signUserOpHash(entryPoint, vm, randomPrivateKey, userOp);
        userOp.signature = signature;
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        vm.expectRevert();
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();
        // verify recipient balance
        assertEq(recipientAddr.balance, 0);
    }

    // run through hook (pass) => validation (pass)
    function testExecuteWithAddressBookPassPreRuntimeHookAndValidation() public {
        address[] memory recipients = new address[](1);
        address recipientAddr = vm.addr(1);
        recipients[0] = recipientAddr;
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);

        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        vm.startPrank(ownerAddr);
        mscaAddr.callWithReturnDataOrRevert(
            0, abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (recipientAddr, 1, "", recipientAddr))
        );
        vm.stopPrank();
        assertEq(recipients[0].balance, 1);
    }

    // run through hook (pass) => validation (fail), not from the owner
    function testExecuteWithAddressBookPassPreRuntimeHookButFailValidation() public {
        address[] memory recipients = new address[](1);
        address recipientAddr = vm.addr(1);
        recipients[0] = recipientAddr;
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        vm.startPrank(vm.addr(123));
        vm.expectRevert(UnauthorizedCaller.selector);
        mscaAddr.callWithReturnDataOrRevert(
            0, abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (recipientAddr, 1, "", recipientAddr))
        );
        vm.stopPrank();
        assertEq(recipients[0].balance, 0);
    }

    // run through hook (fail) => validation (pass)
    function testExecuteWithAddressBookFailPreRuntimeHookButPassValidation() public {
        address[] memory recipients = new address[](0);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);

        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        address randomRecipient = vm.addr(1);
        vm.startPrank(ownerAddr);
        bytes memory revertReason =
            abi.encodeWithSelector(IAddressBookPlugin.UnauthorizedRecipient.selector, ownerAddr, randomRecipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseMSCA.PreRuntimeValidationHookFailed.selector, address(addressBookPlugin), 1, revertReason
            )
        );
        mscaAddr.callWithReturnDataOrRevert(
            0, abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (randomRecipient, 1, "", randomRecipient))
        );
        vm.stopPrank();
        assertEq(randomRecipient.balance, 0);
    }

    // run through hook (fail) => validation (fail)
    function testExecuteWithAddressBookFailPreRuntimeHookAndValidation() public {
        address[] memory recipients = new address[](0);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        address randomRecipient = vm.addr(1);
        // call from random address
        vm.startPrank(vm.addr(123));
        bytes memory revertReason =
            abi.encodeWithSelector(IAddressBookPlugin.UnauthorizedRecipient.selector, vm.addr(123), randomRecipient);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseMSCA.PreRuntimeValidationHookFailed.selector, address(addressBookPlugin), 1, revertReason
            )
        );
        mscaAddr.callWithReturnDataOrRevert(
            0, abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (randomRecipient, 1, "", randomRecipient))
        );
        vm.stopPrank();
        assertEq(randomRecipient.balance, 0);
    }

    function testInstallThenUninstallAddressBookPlugin() public {
        address[] memory recipients = new address[](3);
        recipients[0] = vm.addr(1);
        recipients[1] = vm.addr(2);
        recipients[2] = vm.addr(3);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);

        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.startPrank(ownerAddr);
        bytes memory returnData =
            mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.getAllowedRecipients, (mscaAddr)));
        address[] memory allowedRecipients = abi.decode(returnData, (address[]));
        vm.stopPrank();
        assertEq(allowedRecipients.length, 3);
        assertEq(allowedRecipients[0], recipients[2]);
        assertEq(allowedRecipients[1], recipients[1]);
        assertEq(allowedRecipients[2], recipients[0]);

        // Semi SingleOwnerMSCA doesn't do RUNTIME_VALIDATION_ALWAYS_ALLOW to allow calls from a random address
        // however you can still call into plugin directly to read the data
        vm.startPrank(vm.addr(456));
        vm.expectRevert(UnauthorizedCaller.selector);
        returnData =
            mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.getAllowedRecipients, (mscaAddr)));
        vm.stopPrank();

        allowedRecipients = addressBookPlugin.getAllowedRecipients(mscaAddr);
        assertEq(allowedRecipients.length, 3);

        // now uninstall
        vm.startPrank(ownerAddr);
        msca.uninstallPlugin(addressBookPluginAddr, "", "");
        vm.stopPrank();
        assertEq(msca.getInstalledPlugins().length, 0);
        allowedRecipients = addressBookPlugin.getAllowedRecipients(mscaAddr);
        assertEq(allowedRecipients.length, 0);
    }

    // 1. run through hook (pass) => validation (pass)
    // 2. remove recipient
    // 3. should fail hook now
    function testExecuteWithAddressBookViaUserOpWithERC20PassThenFail() public {
        // install plugin first
        address recipientAddr = vm.addr(1);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        address[] memory recipients = new address[](1);
        recipients[0] = recipientAddr;

        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        testLiquidityPool.mint(mscaAddr, 10);
        address target = address(testLiquidityPool);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(testLiquidityPool.transfer, (recipientAddr, 2));
        uint256 acctNonce = entryPoint.getNonce(mscaAddr, 0);
        bytes memory executeCallData =
            abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (target, value, data, recipientAddr));
        PackedUserOperation memory userOp = buildPartialUserOp(
            mscaAddr,
            acctNonce,
            "0x",
            vm.toString(executeCallData),
            83353,
            1028650,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        bytes memory signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        userOp.signature = signature;
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();
        // verify recipient balance
        assertEq(testLiquidityPool.balanceOf(recipientAddr), 2);

        // remove the recipient now
        vm.startPrank(ownerAddr);
        mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.removeAllowedRecipients, (recipients)));
        vm.stopPrank();

        // do another user op with same calldata this time
        userOp = buildPartialUserOp(
            mscaAddr,
            entryPoint.getNonce(mscaAddr, 0),
            "0x",
            vm.toString(executeCallData),
            83353,
            1028650,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        userOp.signature = signature;
        ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        vm.expectRevert();
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();
        // verify recipient balance now still has 2 tokens as before
        assertEq(testLiquidityPool.balanceOf(recipientAddr), 2);
    }

    // 1. run through hook (fail) => validation (pass)
    // 2. add recipient
    // 3. pass both hook and validation
    function testExecuteWithAddressBookViaUserOpWithERC20FailThenPass() public {
        // install plugin first
        address recipientAddr = vm.addr(1);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        address[] memory recipients = new address[](0);

        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        testLiquidityPool.mint(mscaAddr, 10);
        address target = address(testLiquidityPool);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(testLiquidityPool.transfer, (recipientAddr, 2));
        uint256 acctNonce = entryPoint.getNonce(mscaAddr, 0);
        bytes memory executeCallData =
            abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (target, value, data, recipientAddr));
        PackedUserOperation memory userOp = buildPartialUserOp(
            mscaAddr,
            acctNonce,
            "0x",
            vm.toString(executeCallData),
            83353,
            1028650,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        bytes memory signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        userOp.signature = signature;
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        vm.expectRevert();
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();
        // verify recipient balance
        assertEq(testLiquidityPool.balanceOf(recipientAddr), 0);

        // allow the recipient now
        recipients = new address[](1);
        recipients[0] = recipientAddr;
        vm.startPrank(ownerAddr);
        mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.addAllowedRecipients, (recipients)));
        vm.stopPrank();

        // do another user op with same calldata this time
        userOp = buildPartialUserOp(
            mscaAddr,
            entryPoint.getNonce(mscaAddr, 0),
            "0x",
            vm.toString(executeCallData),
            83353,
            1028650,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        userOp.signature = signature;
        ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();
        // verify recipient balance now has 2 tokens
        assertEq(testLiquidityPool.balanceOf(recipientAddr), 2);
    }

    // 1. run through hook (pass) => validation (pass)
    // 2. remove recipient
    // 3. should fail hook now
    function testExecuteWithAddressBookViaRuntimeWithERC20PassThenFail() public {
        address[] memory recipients = new address[](1);
        address recipientAddr = vm.addr(1);
        recipients[0] = recipientAddr;
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        testLiquidityPool.mint(mscaAddr, 10);
        address target = address(testLiquidityPool);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(testLiquidityPool.transfer, (recipientAddr, 2));
        vm.startPrank(ownerAddr);
        mscaAddr.callWithReturnDataOrRevert(
            0, abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (target, value, data, recipientAddr))
        );
        vm.stopPrank();
        assertEq(testLiquidityPool.balanceOf(recipientAddr), 2);

        // remove the recipient now
        vm.startPrank(ownerAddr);
        mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.removeAllowedRecipients, (recipients)));
        vm.stopPrank();

        // now execute w/o allowed recipient
        vm.startPrank(ownerAddr);
        bytes memory revertReason =
            abi.encodeWithSelector(IAddressBookPlugin.UnauthorizedRecipient.selector, ownerAddr, recipientAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseMSCA.PreRuntimeValidationHookFailed.selector, address(addressBookPlugin), 1, revertReason
            )
        );
        mscaAddr.callWithReturnDataOrRevert(
            0, abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (target, value, data, recipientAddr))
        );
        vm.stopPrank();
        // didn't change
        assertEq(testLiquidityPool.balanceOf(recipientAddr), 2);
    }

    // 1. run through hook (fail) => validation (pass)
    // 2. add recipient
    // 3. pass both hook and validation
    function testExecuteWithAddressBookViaRuntimeWithERC20FailThenPass() public {
        address[] memory recipients = new address[](0);
        // unused now
        address recipientAddr = vm.addr(1);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        testLiquidityPool.mint(mscaAddr, 10);
        address target = address(testLiquidityPool);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(testLiquidityPool.transfer, (recipientAddr, 2));
        vm.startPrank(ownerAddr);
        bytes memory revertReason =
            abi.encodeWithSelector(IAddressBookPlugin.UnauthorizedRecipient.selector, ownerAddr, recipientAddr);
        vm.expectRevert(
            abi.encodeWithSelector(
                BaseMSCA.PreRuntimeValidationHookFailed.selector, address(addressBookPlugin), 1, revertReason
            )
        );
        mscaAddr.callWithReturnDataOrRevert(
            0, abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (target, value, data, recipientAddr))
        );
        vm.stopPrank();
        // didn't change
        assertEq(testLiquidityPool.balanceOf(recipientAddr), 0);

        // add the recipient now
        vm.startPrank(ownerAddr);
        recipients = new address[](1);
        recipients[0] = recipientAddr;
        mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.addAllowedRecipients, (recipients)));
        vm.stopPrank();

        // now execute with allowed recipient
        vm.startPrank(ownerAddr);
        mscaAddr.callWithReturnDataOrRevert(
            0, abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (target, value, data, recipientAddr))
        );
        vm.stopPrank();
        assertEq(testLiquidityPool.balanceOf(recipientAddr), 2);
    }

    function testAddAndRemoveAllowedRecipientsViaRuntime() public {
        // install plugin first
        vm.startPrank(ownerAddr);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        address[] memory recipients = new address[](0);
        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        bytes memory returnData =
            mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.getAllowedRecipients, (mscaAddr)));
        address[] memory allowedRecipients = abi.decode(returnData, (address[]));
        assertEq(allowedRecipients.length, 0);

        address recipientAddr = vm.addr(1);
        recipients = new address[](1);
        recipients[0] = recipientAddr;
        bytes memory executeCallData = abi.encodeCall(IAddressBookPlugin.addAllowedRecipients, (recipients));
        mscaAddr.callWithReturnDataOrRevert(0, executeCallData);
        returnData =
            mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.getAllowedRecipients, (mscaAddr)));
        allowedRecipients = abi.decode(returnData, (address[]));
        assertEq(allowedRecipients.length, 1);
        assertEq(allowedRecipients[0], recipientAddr);

        // add the same recipient again
        executeCallData = abi.encodeCall(IAddressBookPlugin.addAllowedRecipients, (recipients));
        bytes memory revertReason =
            abi.encodeWithSelector(IAddressBookPlugin.FailToAddRecipient.selector, mscaAddr, recipientAddr);
        vm.expectRevert(revertReason);
        mscaAddr.callWithReturnDataOrRevert(0, executeCallData);
        returnData =
            mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.getAllowedRecipients, (mscaAddr)));
        allowedRecipients = abi.decode(returnData, (address[]));
        // didn't change
        assertEq(allowedRecipients.length, 1);
        assertEq(allowedRecipients[0], recipientAddr);

        executeCallData = abi.encodeCall(IAddressBookPlugin.removeAllowedRecipients, (recipients));
        mscaAddr.callWithReturnDataOrRevert(0, executeCallData);
        returnData =
            mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.getAllowedRecipients, (mscaAddr)));
        allowedRecipients = abi.decode(returnData, (address[]));
        assertEq(allowedRecipients.length, 0);

        // delete from empty recipients
        abi.encodeCall(IAddressBookPlugin.removeAllowedRecipients, (recipients));
        revertReason =
            abi.encodeWithSelector(IAddressBookPlugin.FailToRemoveRecipient.selector, mscaAddr, recipientAddr);
        vm.expectRevert(revertReason);
        mscaAddr.callWithReturnDataOrRevert(0, executeCallData);
        returnData =
            mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.getAllowedRecipients, (mscaAddr)));
        allowedRecipients = abi.decode(returnData, (address[]));
        assertEq(allowedRecipients.length, 0);
        vm.stopPrank();

        vm.startPrank(vm.addr(123));
        // add the same recipient again
        executeCallData = abi.encodeCall(IAddressBookPlugin.addAllowedRecipients, (recipients));
        revertReason = abi.encodeWithSelector(UnauthorizedCaller.selector);
        vm.expectRevert(revertReason);
        mscaAddr.callWithReturnDataOrRevert(0, executeCallData);

        // delete from empty recipients
        abi.encodeCall(IAddressBookPlugin.removeAllowedRecipients, (recipients));
        revertReason = abi.encodeWithSelector(UnauthorizedCaller.selector);
        vm.expectRevert(revertReason);
        mscaAddr.callWithReturnDataOrRevert(0, executeCallData);
        vm.stopPrank();
    }

    function testAddAndRemoveAllowedRecipientsViaUserOp() public {
        // install plugin first
        vm.startPrank(ownerAddr);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        address[] memory recipients = new address[](0);

        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        bytes memory returnData =
            mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.getAllowedRecipients, (mscaAddr)));
        address[] memory allowedRecipients = abi.decode(returnData, (address[]));
        assertEq(allowedRecipients.length, 0);

        vm.deal(mscaAddr, 1 ether);
        address recipientAddr = vm.addr(1);
        recipients = new address[](1);
        recipients[0] = recipientAddr;
        uint256 acctNonce = entryPoint.getNonce(mscaAddr, 0);
        bytes memory executeCallData = abi.encodeCall(IAddressBookPlugin.addAllowedRecipients, (recipients));
        PackedUserOperation memory userOp = buildPartialUserOp(
            mscaAddr,
            acctNonce,
            "0x",
            vm.toString(executeCallData),
            83353,
            1028650,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        bytes memory signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        userOp.signature = signature;
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();

        vm.startPrank(ownerAddr);
        returnData =
            mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.getAllowedRecipients, (mscaAddr)));
        allowedRecipients = abi.decode(returnData, (address[]));
        assertEq(allowedRecipients.length, 1);
        assertEq(allowedRecipients[0], recipientAddr);
        vm.stopPrank();

        executeCallData = abi.encodeCall(IAddressBookPlugin.removeAllowedRecipients, (recipients));
        userOp = buildPartialUserOp(
            mscaAddr,
            entryPoint.getNonce(mscaAddr, 0),
            "0x",
            vm.toString(executeCallData),
            83353,
            1028650,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        userOp.signature = signature;
        ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();

        vm.startPrank(ownerAddr);
        returnData =
            mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IAddressBookPlugin.getAllowedRecipients, (mscaAddr)));
        allowedRecipients = abi.decode(returnData, (address[]));
        assertEq(allowedRecipients.length, 0);
        vm.stopPrank();
    }

    // ban execute and executeBatch first
    // ERC20 contract address:
    // 0xc7183455a4C133Ae270771860664b6B7ec320bB1
    // native exec function...
    // fallback...
    // route to plugin...
    // call plugin executeWithAddressBook func...
    // executeFromPluginToExternal...
    // external target:
    // 0xc7183455a4C133Ae270771860664b6B7ec320bB1
    // but since we're banning execute if the account installs the plugin,
    // then it should just revert on
    //    │   │   └─ ← InvalidHookFunctionId(2)
    //    │   └─ ← FailedOp(0, "AA23 reverted (or OOG)")
    //
    // then lift the ban by uninstalling address book plugin
    function testWrapExecuteWithAddressBookWithExecuteViaUserOp() public {
        // install plugin first
        address recipientAddr = vm.addr(1);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        address[] memory recipients = new address[](1);
        recipients[0] = recipientAddr;

        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 2 ether);
        testLiquidityPool.mint(mscaAddr, 10);
        address target = address(testLiquidityPool);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(testLiquidityPool.transfer, (recipientAddr, 2));
        uint256 acctNonce = entryPoint.getNonce(mscaAddr, 0);
        bytes memory executeWithAddressBookCallData =
            abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (target, value, data, recipientAddr));
        bytes memory executeCallData =
            abi.encodeCall(IStandardExecutor.execute, (mscaAddr, 0, executeWithAddressBookCallData));
        PackedUserOperation memory userOp = buildPartialUserOp(
            mscaAddr,
            acctNonce,
            "0x",
            vm.toString(executeCallData),
            1005335,
            103353,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        bytes memory signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        userOp.signature = signature;
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        vm.expectRevert();
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();
        // verify recipient balance is still 0
        assertEq(testLiquidityPool.balanceOf(recipientAddr), 0);

        // now I'm uninstalling the plugin
        // uninstall it
        vm.startPrank(ownerAddr);
        msca.uninstallPlugin(addressBookPluginAddr, "", "");
        vm.stopPrank();
        assertEq(msca.getInstalledPlugins().length, 0);

        // submit the userOp with regular execute
        executeCallData = abi.encodeCall(IStandardExecutor.execute, (address(testLiquidityPool), 0, data));
        userOp = buildPartialUserOp(
            mscaAddr,
            entryPoint.getNonce(mscaAddr, 0),
            "0x",
            vm.toString(executeCallData),
            1005335,
            103353,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        userOp.signature = signature;
        ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();
        assertEq(testLiquidityPool.balanceOf(recipientAddr), 2);
    }

    //  ban execute and executeBatch first
    //  ERC20 contract address:
    //  0xc7183455a4C133Ae270771860664b6B7ec320bB1
    //  native exec function...
    //  fallback...
    //  route to plugin...
    //  call plugin executeWithAddressBook func...
    //  executeFromPluginToExternal...
    //  external target:
    //  0xc7183455a4C133Ae270771860664b6B7ec320bB1
    //
    //  then lift the ban by uninstalling address book plugin
    function testWrapExecuteWithAddressBookWithExecuteViaRuntime() public {
        address[] memory recipients = new address[](1);
        address recipientAddr = vm.addr(1);
        recipients[0] = recipientAddr;
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);

        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        testLiquidityPool.mint(mscaAddr, 10);
        address target = address(testLiquidityPool);
        uint256 value = 0;
        bytes memory data = abi.encodeCall(testLiquidityPool.transfer, (recipientAddr, 2));
        vm.startPrank(ownerAddr);
        // 2 is PRE_HOOK_ALWAYS_DENY_FUNCTION_REFERENCE
        vm.expectRevert(abi.encodeWithSelector(InvalidValidationFunctionId.selector, 2));
        msca.execute(
            mscaAddr, 0, abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (target, value, data, recipientAddr))
        );
        vm.stopPrank();
        // balance didn't change at all
        assertEq(testLiquidityPool.balanceOf(recipientAddr), 0);

        // now I'm uninstalling the plugin
        // uninstall it
        vm.startPrank(ownerAddr);
        msca.uninstallPlugin(addressBookPluginAddr, "", "");
        vm.stopPrank();
        assertEq(msca.getInstalledPlugins().length, 0);

        // call regular execute
        target = address(testLiquidityPool);
        value = 0;
        data = abi.encodeCall(testLiquidityPool.transfer, (recipientAddr, 2));
        vm.startPrank(ownerAddr);
        msca.execute(mscaAddr, 0, abi.encodeCall(IStandardExecutor.execute, (target, value, data)));
        vm.stopPrank();
        assertEq(testLiquidityPool.balanceOf(recipientAddr), 2);
    }

    function testExecuteBatchWithAddressBookViaRuntimeWithERC20Transfer() public {
        address[] memory recipients = new address[](2);
        recipients[0] = vm.addr(1);
        recipients[1] = vm.addr(2);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        testLiquidityPool.mint(mscaAddr, 10);
        address[] memory target = new address[](2);
        uint256[] memory value = new uint256[](2);
        bytes[] memory data = new bytes[](2);
        target[0] = address(testLiquidityPool);
        target[1] = address(testLiquidityPool);
        value[0] = 0;
        value[1] = 0;
        data[0] = abi.encodeCall(testLiquidityPool.transfer, (recipients[0], 2));
        data[1] = abi.encodeCall(testLiquidityPool.transfer, (recipients[1], 3));
        vm.startPrank(ownerAddr);
        mscaAddr.callWithReturnDataOrRevert(
            0, abi.encodeCall(AddressBookPlugin.executeBatchWithAddressBook, (target, value, data, recipients))
        );
        vm.stopPrank();
        assertEq(testLiquidityPool.balanceOf(recipients[0]), 2);
        assertEq(testLiquidityPool.balanceOf(recipients[1]), 3);
    }

    function testExecuteBatchWithAddressBookViaUserOpWithERC20() public {
        // install plugin first
        address[] memory recipients = new address[](2);
        recipients[0] = vm.addr(1);
        recipients[1] = vm.addr(2);
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.deal(mscaAddr, 1 ether);
        testLiquidityPool.mint(mscaAddr, 10);
        address[] memory target = new address[](2);
        uint256[] memory value = new uint256[](2);
        bytes[] memory data = new bytes[](2);
        target[0] = address(testLiquidityPool);
        target[1] = address(testLiquidityPool);
        value[0] = 0;
        value[1] = 0;
        data[0] = abi.encodeCall(testLiquidityPool.transfer, (recipients[0], 2));
        data[1] = abi.encodeCall(testLiquidityPool.transfer, (recipients[1], 3));
        uint256 acctNonce = entryPoint.getNonce(mscaAddr, 0);
        bytes memory executeCallData =
            abi.encodeCall(AddressBookPlugin.executeBatchWithAddressBook, (target, value, data, recipients));
        PackedUserOperation memory userOp = buildPartialUserOp(
            mscaAddr,
            acctNonce,
            "0x",
            vm.toString(executeCallData),
            833530,
            1028650,
            45484,
            516219199704,
            1130000000,
            "0x"
        );

        bytes memory signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        userOp.signature = signature;
        PackedUserOperation[] memory ops = new PackedUserOperation[](1);
        ops[0] = userOp;
        vm.startPrank(address(entryPoint));
        entryPoint.handleOps(ops, beneficiary);
        vm.stopPrank();
        // verify recipient balance
        assertEq(testLiquidityPool.balanceOf(recipients[0]), 2);
        assertEq(testLiquidityPool.balanceOf(recipients[1]), 3);
    }

    function testSkipInstallingAnyRecipientForSemi() public {
        vm.deal(ownerAddr, 10e18);
        vm.startPrank(ownerAddr, ownerAddr);
        bytes memory _initializingData = abi.encode(ownerAddr);
        console.log(
            "\nOwner(%s) calls < SingleOwnerMSCAFactory.createAccount(senderAddr, bytes32(0), _initializingData) >",
            ownerAddr
        );
        msca = factory.createAccount(ownerAddr, bytes32(0), _initializingData);
        console.log("address(msca) -> %s", address(msca));
        (bool sent,) = address(msca).call{value: 10e18}("");
        require(sent, "Failed to send Ether");
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        Call[] memory _calls = new Call[](1);
        address[] memory recipients = new address[](0);
        _calls[0].target = address(msca);
        _calls[0].value = 0;
        _calls[0].data = abi.encodeCall(
            IPluginManager.installPlugin,
            (addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies)
        );
        console.log("\nOwner(%s) calls < executeBatch(_calls) >", ownerAddr);
        msca.executeBatch(_calls);
        address destAddr = makeAddr("testSkipInstallingAnyRecipient_dest");
        address target = destAddr;
        uint256 value = 4e18;
        bytes memory data = "";
        address recipient = address(0);
        bytes memory executeCallData =
            abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (target, value, data, recipient));
        PackedUserOperation memory userOp =
            buildPartialUserOp(address(msca), 0, "0x", vm.toString(executeCallData), 5000000, 20000000, 0, 2, 1, "0x");
        bytes32 userOpHash = entryPoint.getUserOpHash(userOp);
        userOp.signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        PackedUserOperation[] memory userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        console.log("");
        console.log("address(msca).balance -> %s", address(msca).balance);
        console.log("address(dest).balance -> %s", address(destAddr).balance);
        console.log("\nOwner(%s) calls < entryPoint.handleOps(userOps, msca) >", ownerAddr);
        entryPoint.handleOps(userOps, payable(address(msca)));
        console.log("");
        console.log("address(msca).balance -> %s", address(msca).balance);
        console.log("address(dest).balance -> %s", address(destAddr).balance);
        assertEq(address(destAddr).balance, 4e18);

        // test execute batch
        address[] memory targets = new address[](1);
        uint256[] memory values = new uint256[](1);
        bytes[] memory dataArr = new bytes[](1);
        address[] memory verifiedRecipients = new address[](1);
        targets[0] = destAddr;
        values[0] = 4e18;
        verifiedRecipients[0] = address(0);
        executeCallData = abi.encodeCall(
            AddressBookPlugin.executeBatchWithAddressBook, (targets, values, dataArr, verifiedRecipients)
        );
        userOp =
            buildPartialUserOp(address(msca), 1, "0x", vm.toString(executeCallData), 5000000, 20000000, 0, 2, 1, "0x");
        userOpHash = entryPoint.getUserOpHash(userOp);
        userOp.signature = signUserOpHash(entryPoint, vm, eoaPrivateKey, userOp);
        userOps = new PackedUserOperation[](1);
        userOps[0] = userOp;
        console.log("");
        console.log("address(msca).balance -> %s", address(msca).balance);
        console.log("address(dest).balance -> %s", address(destAddr).balance);
        console.log("\nOwner(%s) calls < entryPoint.handleOps(userOps, msca) >", ownerAddr);
        entryPoint.handleOps(userOps, payable(address(msca)));
        console.log("");
        console.log("address(msca).balance -> %s", address(msca).balance);
        console.log("address(dest).balance -> %s", address(destAddr).balance);
        assertEq(address(destAddr).balance, 8e18);
        vm.stopPrank();
    }

    // this combo test case was already covered by different test suites,
    // but I'm still adding it so developers don't need to look up from scattered files.
    // 1. start without address book plugin
    // 2. transfer
    // 3. then install address book plugin
    // 4. transfer with executeWithAddressBook (allowed)
    // 5. transfer with execute (banned)
    function testExecuteWithoutAddressBookThenWithAddressBook() public {
        address recipientAddr = vm.addr(1);
        vm.deal(mscaAddr, 1 ether);
        vm.startPrank(ownerAddr);
        mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IStandardExecutor.execute, (recipientAddr, 1, "")));
        vm.stopPrank();
        assertEq(recipientAddr.balance, 1);

        address[] memory recipients = new address[](1);
        recipients[0] = recipientAddr;
        FunctionReference[] memory dependencies = new FunctionReference[](2);
        dependencies[0] =
            FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_RUNTIME_VALIDATION_OWNER_OR_SELF));
        dependencies[1] = FunctionReference(mscaAddr, uint8(SingleOwnerMSCA.FunctionId.NATIVE_USER_OP_VALIDATION_OWNER));
        vm.startPrank(ownerAddr);
        msca.installPlugin(addressBookPluginAddr, addressBookPluginManifest, abi.encode(recipients), dependencies);
        vm.stopPrank();

        vm.startPrank(ownerAddr);
        mscaAddr.callWithReturnDataOrRevert(
            0, abi.encodeCall(AddressBookPlugin.executeWithAddressBook, (recipientAddr, 1, "", recipientAddr))
        );
        vm.stopPrank();
        assertEq(recipients[0].balance, 2); // 1 + 1

        vm.startPrank(ownerAddr);
        vm.expectRevert(abi.encodeWithSelector(InvalidValidationFunctionId.selector, 2));
        mscaAddr.callWithReturnDataOrRevert(0, abi.encodeCall(IStandardExecutor.execute, (recipientAddr, 1, "")));
        vm.stopPrank();
        // hasn't changed
        assertEq(recipients[0].balance, 2);
    }

    function testNotImplementedFuncs() public {
        uint8 functionId;
        PackedUserOperation memory uo;
        bytes32 userOpHash;
        vm.expectRevert(
            abi.encodeWithSelector(NotImplemented.selector, BasePlugin.userOpValidationFunction.selector, functionId)
        );
        addressBookPlugin.userOpValidationFunction(functionId, uo, userOpHash);

        address sender;
        uint256 value;
        bytes memory data;
        vm.expectRevert(
            abi.encodeWithSelector(NotImplemented.selector, BasePlugin.runtimeValidationFunction.selector, functionId)
        );
        addressBookPlugin.runtimeValidationFunction(functionId, sender, value, data);

        vm.expectRevert(
            abi.encodeWithSelector(NotImplemented.selector, BasePlugin.preExecutionHook.selector, functionId)
        );
        addressBookPlugin.preExecutionHook(functionId, sender, value, data);

        vm.expectRevert(
            abi.encodeWithSelector(NotImplemented.selector, BasePlugin.postExecutionHook.selector, functionId)
        );
        addressBookPlugin.postExecutionHook(functionId, data);
    }
}
