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

import {PLUGIN_AUTHOR, PLUGIN_VERSION_1, SIG_VALIDATION_SUCCEEDED} from "../../../../src/common/Constants.sol";
import "../../../../src/msca/6900/v0.7/common/Structs.sol";

import "../../../../src/msca/6900/v0.7/interfaces/IPluginExecutor.sol";
import "../../../../src/msca/6900/v0.7/interfaces/IPluginManager.sol";
import "../../../../src/msca/6900/v0.7/interfaces/IStandardExecutor.sol";

import "../../../../src/msca/6900/v0.7/plugins/BasePlugin.sol";
import "../../../../src/msca/6900/v0.7/plugins/v1_0_0/acl/ISingleOwnerPlugin.sol";
import "../../../util/TestLiquidityPool.sol";
import "@account-abstraction/contracts/interfaces/PackedUserOperation.sol";
import "forge-std/src/console.sol";

/**
 * @dev Plugin that only has post hooks.
 */
contract TestTokenWithPostHookOnlyPlugin is BasePlugin {
    error InvalidSender(address addr);
    error InvalidReceiver(address addr);
    error InsufficientBalance(address addr, uint256 bal, uint256 value);

    enum FunctionId {
        USER_OP_VALIDATION,
        RUNTIME_VALIDATION,
        POST_EXECUTION_HOOK
    }

    string public constant NAME = "Test Token Plugin With Post Hook Only";
    string constant NOT_FROZEN_PERM = "NOT_FROZEN_PERM"; // msg.sender should be able to

    mapping(address => uint256) internal _balances;
    // use constants generated from tests here so manifest can stay pure
    address public constant longLiquidityPoolAddr = 0x7bff7C664bFeF913FB04473CC610D41F35E2A3F9;
    address public constant shortLiquidityPoolAddr = 0x241BB07f7eBB2CDC08Ccb8130088a8C3761cf197;

    /// executeFromPlugin is allowed
    /// airdrop from wallet to owner
    function airdropToken(uint256 value) external returns (address) {
        bytes memory result =
            IPluginExecutor(msg.sender).executeFromPlugin(abi.encodeCall(ISingleOwnerPlugin.getOwnerOf, (msg.sender)));
        address addr = abi.decode(result, (address));
        _balances[addr] += value;
        _balances[msg.sender] -= value;
        return addr;
    }

    /// no permission
    function airdropTokenBad(uint256 value) external {
        bytes memory result =
            IPluginExecutor(msg.sender).executeFromPlugin(abi.encodeCall(ISingleOwnerPlugin.getOwnerOf, (msg.sender)));
        address addr = abi.decode(result, (address));
        _balances[addr] += value;
        _balances[msg.sender] -= value;
        // trying to sneak in some code to mess up the owner
        IPluginExecutor(msg.sender).executeFromPlugin(
            abi.encodeCall(ISingleOwnerPlugin.transferOwnership, (address(0x0)))
        );
    }

    function executeFromPluginNotAllowed() external returns (bytes memory) {
        return IPluginExecutor(msg.sender).executeFromPlugin(
            abi.encodeCall(ISingleOwnerPlugin.transferOwnership, (msg.sender))
        );
    }

    // externalFromPluginExternal is allowed
    // mint to both liquidity pools
    function mintToken(uint256 value) external {
        IPluginExecutor(msg.sender).executeFromPluginExternal(
            longLiquidityPoolAddr, 0, abi.encodeCall(TestLiquidityPool.mint, (msg.sender, value))
        );
        IPluginExecutor(msg.sender).executeFromPluginExternal(
            shortLiquidityPoolAddr, 0, abi.encodeCall(TestLiquidityPool.mint, (msg.sender, value))
        );
    }

    // externalFromPluginExternal is allowed
    // supply to only long liquidity pool
    function supplyLiquidity(address to, uint256 value) external {
        IPluginExecutor(msg.sender).executeFromPluginExternal(
            longLiquidityPoolAddr, 0, abi.encodeCall(TestLiquidityPool.supplyLiquidity, (msg.sender, to, value))
        );
    }

    // externalFromPluginExternal is not allowed
    function supplyLiquidityBad(address to, uint256 value) external {
        IPluginExecutor(msg.sender).executeFromPluginExternal(
            shortLiquidityPoolAddr, 0, abi.encodeCall(TestLiquidityPool.supplyLiquidity, (msg.sender, to, value))
        );
    }

    function transferToken(address to, uint256 value) external {
        _transferToken(to, value);
    }

    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    /// @inheritdoc BasePlugin
    function onInstall(bytes calldata data) external override {
        // airdrop token
        _balances[msg.sender] = abi.decode(data, (uint256));
    }

    /// @inheritdoc BasePlugin
    function onUninstall(bytes calldata data) external override {
        // reclaim token
        (address destination, uint256 value) = abi.decode(data, (address, uint256));
        _transferToken(destination, value);
        // destroy the remaining balance
        delete _balances[msg.sender];
    }

    /// @inheritdoc BasePlugin
    function userOpValidationFunction(uint8 functionId, PackedUserOperation calldata userOp, bytes32 userOpHash)
        external
        pure
        override
        returns (uint256 validationData)
    {
        (userOp, userOpHash);
        if (functionId == uint8(FunctionId.USER_OP_VALIDATION)) {
            return SIG_VALIDATION_SUCCEEDED;
        }
        revert NotImplemented(msg.sig, functionId);
    }

    /// @inheritdoc BasePlugin
    function runtimeValidationFunction(uint8 functionId, address sender, uint256 value, bytes calldata data)
        external
        pure
        override
    {
        (sender, value, data);
        if (functionId == uint8(FunctionId.RUNTIME_VALIDATION)) {
            return;
        }
        revert NotImplemented(msg.sig, functionId);
    }

    /// @inheritdoc BasePlugin
    function postExecutionHook(uint8 functionId, bytes calldata preExecHookData) external pure override {
        console.logString("postExecutionHook data:");
        console.logBytes(preExecHookData);
        require(preExecHookData.length == 0, "postOnlyHook should not have data");
        if (functionId == uint8(FunctionId.POST_EXECUTION_HOOK)) {
            return;
        } else if (functionId == uint8(FunctionId.POST_EXECUTION_HOOK)) {
            return;
        }
        revert NotImplemented(msg.sig, functionId);
    }

    /// @inheritdoc BasePlugin
    function pluginManifest() external pure override returns (PluginManifest memory) {
        PluginManifest memory manifest;
        /// executionFunctions
        manifest.executionFunctions = new bytes4[](7);
        // Execution functions defined in this plugin to be installed on the MSCA.
        manifest.executionFunctions[0] = this.transferToken.selector;
        manifest.executionFunctions[1] = this.balanceOf.selector;
        manifest.executionFunctions[2] = this.airdropToken.selector;
        manifest.executionFunctions[3] = this.airdropTokenBad.selector;
        manifest.executionFunctions[4] = this.mintToken.selector;
        manifest.executionFunctions[5] = this.supplyLiquidity.selector;
        manifest.executionFunctions[6] = this.supplyLiquidityBad.selector;

        /// permittedExecutionSelectors
        // Native functions or execution functions already installed on the MSCA that this plugin will be
        // able to call. The actual hooks will be provided by manifest.permittedCallHooks or
        // installPlugin(injectedHooks).
        manifest.permittedExecutionSelectors = new bytes4[](1);
        // request to access SingleOwnerPlugin.getOwnerOf only
        manifest.permittedExecutionSelectors[0] = ISingleOwnerPlugin.getOwnerOf.selector;

        /// permittedExternalCalls
        bytes4[] memory permittedExternalCallsSelectors = new bytes4[](1);
        permittedExternalCallsSelectors[0] = TestLiquidityPool.mint.selector;
        manifest.permittedExternalCalls = new ManifestExternalCallPermission[](2);
        // access only mint function in shortLiquidityPool
        manifest.permittedExternalCalls[0] = ManifestExternalCallPermission({
            externalAddress: shortLiquidityPoolAddr,
            permitAnySelector: false,
            selectors: permittedExternalCallsSelectors
        });
        // access all the functions in longLiquidityPool
        manifest.permittedExternalCalls[1] = ManifestExternalCallPermission({
            externalAddress: longLiquidityPoolAddr,
            permitAnySelector: true,
            selectors: new bytes4[](0)
        });

        /// userOpValidationFunctions
        ManifestFunction memory userOpValidationAssociatedFunction =
            ManifestFunction(ManifestAssociatedFunctionType.SELF, uint8(FunctionId.USER_OP_VALIDATION), 0);
        // the following function calls (from entry point) should be gated by the userOpValidationAssociatedFunction
        manifest.userOpValidationFunctions = new ManifestAssociatedFunction[](manifest.executionFunctions.length);
        // plugin functions
        // if the same executionSelector has already gated by other plugin.userOpValidationFunction, re-installation
        // will revert
        for (uint256 i = 0; i < manifest.executionFunctions.length; ++i) {
            manifest.userOpValidationFunctions[i] =
                ManifestAssociatedFunction(manifest.executionFunctions[i], userOpValidationAssociatedFunction);
        }

        /// preUserOpValidationHooks
        manifest.preUserOpValidationHooks = new ManifestAssociatedFunction[](0);

        /// runtimeValidationFunctions
        ManifestFunction memory runtimeValidationAssociatedFunction =
            ManifestFunction(ManifestAssociatedFunctionType.SELF, uint8(FunctionId.RUNTIME_VALIDATION), 0);
        manifest.runtimeValidationFunctions = new ManifestAssociatedFunction[](manifest.executionFunctions.length);
        // plugin functions
        for (uint256 i = 0; i < manifest.executionFunctions.length; ++i) {
            manifest.runtimeValidationFunctions[i] =
                ManifestAssociatedFunction(manifest.executionFunctions[i], runtimeValidationAssociatedFunction);
        }

        /// preRuntimeValidationHooks
        manifest.preRuntimeValidationHooks = new ManifestAssociatedFunction[](0);

        /// executionHooks
        manifest.executionHooks = new ManifestExecutionHook[](3);
        manifest.executionHooks[0] = ManifestExecutionHook({
            selector: this.transferToken.selector,
            preExecHook: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.NONE,
                functionId: 0,
                dependencyIndex: 0
            }),
            postExecHook: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.SELF,
                functionId: uint8(FunctionId.POST_EXECUTION_HOOK),
                dependencyIndex: 0
            })
        });
        manifest.executionHooks[1] = ManifestExecutionHook({
            selector: this.airdropToken.selector,
            preExecHook: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.NONE,
                functionId: 0,
                dependencyIndex: 0
            }),
            postExecHook: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.SELF,
                functionId: uint8(FunctionId.POST_EXECUTION_HOOK),
                dependencyIndex: 0
            })
        });
        manifest.executionHooks[2] = ManifestExecutionHook({
            selector: this.airdropTokenBad.selector,
            preExecHook: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.NONE,
                functionId: 0,
                dependencyIndex: 0
            }),
            postExecHook: ManifestFunction({
                functionType: ManifestAssociatedFunctionType.SELF,
                functionId: uint8(FunctionId.POST_EXECUTION_HOOK),
                dependencyIndex: 0
            })
        });

        manifest.dependencyInterfaceIds = new bytes4[](1);
        manifest.dependencyInterfaceIds[0] = type(ISingleOwnerPlugin).interfaceId;
        return manifest;
    }

    /// @inheritdoc BasePlugin
    function pluginMetadata() external pure virtual override returns (PluginMetadata memory) {
        PluginMetadata memory metadata;
        metadata.name = NAME;
        metadata.version = PLUGIN_VERSION_1;
        metadata.author = PLUGIN_AUTHOR;

        // Permission descriptions
        metadata.permissionDescriptors = new SelectorPermission[](1);
        metadata.permissionDescriptors[0] =
            SelectorPermission({functionSelector: this.transferToken.selector, permissionDescription: NOT_FROZEN_PERM});
        return metadata;
    }

    function _transferToken(address to, uint256 value) internal {
        // TODO: pass the from address the function param
        address from = msg.sender;
        if (from == address(0)) {
            revert InvalidSender(address(0));
        }
        if (to == address(0)) {
            revert InvalidReceiver(address(0));
        }
        uint256 fromBalance = _balances[from];
        if (fromBalance < value) {
            revert InsufficientBalance(from, fromBalance, value);
        }
        _balances[from] = fromBalance - value;
        _balances[to] += value;
    }
}
