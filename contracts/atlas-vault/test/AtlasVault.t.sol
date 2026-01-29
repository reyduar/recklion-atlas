// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// Test: Clase base de Foundry que provee utilities para testing
// Incluye: vm.prank, vm.expectRevert, assertEq, etc.
import {Test} from "forge-std/Test.sol";

// El contrato que vamos a testear
import {AtlasVault} from "../src/AtlasVault.sol";

// Token mock para simular depósitos y retiros
import {MockERC20} from "./mocks/MockERC20.sol";

/**
 * @title AtlasVaultTest
 * @notice Suite de tests para el contrato AtlasVault
 * @dev Utiliza Foundry para testing
 *
 *      Estructura de un test de Foundry:
 *      1. setUp() - Se ejecuta antes de cada test
 *      2. test*() - Funciones de test individuales
 *      3. Assertions - Validaciones (assertEq, assertTrue, etc.)
 *
 *      Cheatcodes de Foundry usados:
 *      - vm.startPrank/stopPrank: Simula llamadas desde otra address
 *      - vm.prank: Simula una única llamada desde otra address
 *      - vm.expectRevert: Espera que la siguiente llamada falle
 */
contract AtlasVaultTest is Test {
    // ============================================
    // VARIABLES DE ESTADO
    // ============================================

    // Instancias de los contratos a testear
    AtlasVault vault; // El vault que estamos probando
    MockERC20 token; // Token ERC20 mock para pruebas

    // Addresses de prueba con nombres mnemotécnicos
    address admin = address(0xA11CE); // Administrador del vault (Alice)
    address operator_ = address(0xB0B); // Operador autorizado (Bob)
    address user = address(0xCAFE); // Usuario normal que deposita
    address recipient = address(0xD00D); // Beneficiario de depósitos
    address to = address(0xBEEF); // Destino de retiros            // Destino de retiros

    // ============================================
    // SETUP
    // ============================================

    /**
     * @notice Configuración inicial que se ejecuta antes de cada test
     * @dev Esta función se llama automáticamente por Foundry antes de cada test
     *
     *      Setup realizado:
     *      1. Deploy del vault con admin
     *      2. Otorgar rol de operador a operator_
     *      3. Crear token mock
     *      4. Mintear tokens iniciales al usuario de prueba
     *
     *      vm.startPrank(admin): Todas las llamadas siguientes se ejecutan como 'admin'
     *      vm.stopPrank(): Detiene la simulación de address
     */
    function setUp() public {
        // Configurar el vault como admin
        vm.startPrank(admin);
        vault = new AtlasVault(admin); // Deploy del vault
        vault.grantOperator(operator_); // Autorizar operador
        vm.stopPrank(); // Volver a msg.sender normal

        // Crear token de prueba y dar balance inicial al usuario
        token = new MockERC20("Mock", "MOCK");
        token.mint(user, 1_000e18); // Usuario tiene 1000 tokens
    }

    // ============================================
    // TESTS - DEPÓSITOS
    // ============================================

    /**
     * @notice Test: Verificar que los depósitos mueven fondos correctamente
     * @dev Este test valida:
     *      ✅ El usuario puede aprobar tokens al vault
     *      ✅ depositToken() transfiere tokens del usuario al vault
     *      ✅ El balance del vault aumenta correctamente
     *
     *      Flujo del test:
     *      1. Usuario aprueba 10 tokens al vault
     *      2. Usuario deposita 10 tokens
     *      3. Verificar que el vault tiene 10 tokens
     */
    function testDepositMovesFunds() public {
        uint256 amount = 10e18; // 10 tokens (con 18 decimales)

        // Simular acciones del usuario
        vm.startPrank(user);
        token.approve(address(vault), amount); // Paso 1: Approve
        vault.depositToken(address(token), amount, recipient); // Paso 2: Deposit
        vm.stopPrank();

        // Verificar que los tokens están en el vault
        assertEq(token.balanceOf(address(vault)), amount);
    }

    // ============================================
    // TESTS - RETIROS Y PERMISOS
    // ============================================

    /**
     * @notice Test: Verificar que solo operadores pueden ejecutar retiros
     * @dev Este test valida el control de acceso:
     *      ✅ Usuarios normales NO pueden llamar withdrawToken()
     *      ✅ Solo addresses con OPERATOR_ROLE pueden retirar
     *      ✅ Los retiros transfieren fondos correctamente
     *
     *      Flujo del test:
     *      1. Usuario deposita 5 tokens en el vault
     *      2. Usuario intenta retirar → debe fallar (sin permisos)
     *      3. Operador retira → debe funcionar
     *      4. Verificar que los tokens llegaron al destino
     *
     *      vm.expectRevert(): La siguiente transacción debe fallar
     *      Si no falla, el test falla
     */
    function testWithdrawOnlyOperator() public {
        uint256 amount = 5e18; // 5 tokens

        // Paso 1: Usuario deposita tokens
        vm.startPrank(user);
        token.approve(address(vault), amount);
        vault.depositToken(address(token), amount, user);
        vm.stopPrank();

        // Paso 2: Usuario sin permisos intenta retirar → debe fallar
        vm.prank(user); // Siguiente llamada será como 'user'
        vm.expectRevert(); // Esperamos que falle
        vault.withdrawToken(address(token), amount, to, keccak256("wid"));

        // Paso 3: Operador autorizado retira → debe funcionar
        vm.prank(operator_); // Siguiente llamada será como 'operator_'
        vault.withdrawToken(address(token), amount, to, keccak256("wid"));

        // Paso 4: Verificar que los tokens llegaron al destino
        assertEq(token.balanceOf(to), amount);
    }
}
