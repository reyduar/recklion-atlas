// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AtlasVault} from "../src/AtlasVault.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract AtlasVaultTest is Test {
    AtlasVault vault;
    MockERC20 token;

    address admin = address(0xA11CE);
    address operator_ = address(0xB0B);
    address user = address(0xCAFE);
    address recipient = address(0xD00D);
    address to = address(0xBEEF);

    function setUp() public {
        vm.startPrank(admin);
        vault = new AtlasVault(admin);
        vault.grantOperator(operator_);
        vm.stopPrank();

        token = new MockERC20("Mock", "MOCK");
        token.mint(user, 1_000e18);
    }

    function testDepositMovesFunds() public {
        uint256 amount = 10e18;

        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.depositToken(address(token), amount, recipient);
        vm.stopPrank();

        assertEq(token.balanceOf(address(vault)), amount);
    }

    function testWithdrawOnlyOperator() public {
        uint256 amount = 5e18;

        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.depositToken(address(token), amount, user);
        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert();
        vault.withdrawToken(address(token), amount, to, keccak256("wid"));

        vm.prank(operator_);
        vault.withdrawToken(address(token), amount, to, keccak256("wid"));

        assertEq(token.balanceOf(to), amount);
    }
}
