// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// IERC20: Interfaz estándar para interactuar con tokens ERC20
// Permite llamar a funciones como balanceOf, transfer, approve, etc.
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// SafeERC20: Wrapper seguro para operaciones ERC20
// Protege contra tokens que no devuelven bool correctamente en transfer/transferFrom
// Previene problemas con tokens no estándar
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// AccessControl: Sistema de roles y permisos basado en roles (RBAC)
// Permite definir roles como ADMIN, OPERATOR y controlar quién puede ejecutar qué
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

// Pausable: Patrón circuit breaker para pausar el contrato en emergencias
// Permite detener depósitos/retiros si se detecta un problema de seguridad
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

// ReentrancyGuard: Protección contra ataques de reentrancia
// Previene que una función sea llamada recursivamente antes de completar su ejecución
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title AtlasVault
 * @notice Contrato de custodia (vault) para gestionar depósitos y retiros de tokens ERC20
 * @dev Implementa un sistema seguro de vault con las siguientes características:
 *      - Control de acceso basado en roles (admin y operadores)
 *      - Pausabilidad para emergencias
 *      - Protección contra reentrancia
 *      - Emisión de eventos para indexación off-chain
 *
 * Flujo de funcionamiento:
 * 1. Usuarios depositan tokens → se genera un depositId único
 * 2. Usuarios solicitan retiros → se genera un withdrawalId
 * 3. Operadores ejecutan retiros aprobados → se envían los fondos
 *
 * Este contrato NO mantiene balances por usuario internamente.
 * La contabilidad se maneja off-chain escuchando los eventos.
 */
contract AtlasVault is AccessControl, Pausable, ReentrancyGuard {
    // Habilita el uso de funciones seguras (safeTransfer, safeTransferFrom)
    // para cualquier token IERC20
    // Habilita el uso de funciones seguras (safeTransfer, safeTransferFrom)
    // para cualquier token IERC20
    using SafeERC20 for IERC20;

    // ============================================
    // ROLES Y CONSTANTES
    // ============================================

    /**
     * @notice Rol de operador autorizado para ejecutar retiros
     * @dev Los operadores son addresses de confianza (ej: servicios backend)
     *      que pueden ejecutar retiros una vez aprobados por el sistema off-chain
     */
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    // ============================================
    // EVENTOS
    // ============================================

    /**
     * @notice Se emite cuando un usuario deposita tokens en el vault
     * @dev Este evento es crucial para el sistema off-chain:
     *      - El backend escucha este evento para acreditar balance al usuario
     *      - depositId es único y permite tracking del depósito
     * @param token Dirección del token ERC20 depositado
     * @param from Usuario que realizó el depósito
     * @param recipient Beneficiario del depósito (puede ser diferente al sender)
     * @param amount Cantidad de tokens depositados
     * @param depositId ID único del depósito (hash generado on-chain)
     */
    event Deposit(
        address indexed token,
        address indexed from,
        address indexed recipient,
        uint256 amount,
        bytes32 depositId
    );

    /**
     * @notice Se emite cuando un usuario solicita un retiro
     * @dev El backend escucha esto para:
     *      - Aplicar reglas de riesgo
     *      - Validar balances off-chain
     *      - Aprobar o rechazar el retiro
     * @param token Token a retirar
     * @param requester Usuario que solicita el retiro
     * @param to Dirección destino del retiro
     * @param amount Cantidad a retirar
     * @param withdrawalId ID único de la solicitud de retiro
     */
    event WithdrawalRequested(
        address indexed token,
        address indexed requester,
        address indexed to,
        uint256 amount,
        bytes32 withdrawalId
    );

    /**
     * @notice Se emite cuando un operador ejecuta un retiro aprobado
     * @dev Confirma que los fondos salieron del vault
     * @param token Token retirado
     * @param operator Operador que ejecutó el retiro
     * @param to Dirección que recibió los fondos
     * @param amount Cantidad retirada
     * @param withdrawalId ID del retiro (debe coincidir con WithdrawalRequested)
     */
    event WithdrawalExecuted(
        address indexed token,
        address indexed operator,
        address indexed to,
        uint256 amount,
        bytes32 withdrawalId
    );

    // ============================================
    // CONSTRUCTOR
    // ============================================

    /**
     * @notice Inicializa el contrato y asigna el rol de administrador
     * @dev El admin tiene control total:
     *      - Puede pausar/despausar el contrato
     *      - Puede otorgar/revocar roles de operador
     *      - Hereda DEFAULT_ADMIN_ROLE de AccessControl
     * @param admin Dirección que recibirá privilegios de administrador
     */
    constructor(address admin) {
        require(admin != address(0), "admin=0");
        // Otorga el rol de admin principal al deployer o address especificado
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    // ============================================
    // FUNCIONES PÚBLICAS - DEPÓSITOS
    // ============================================

    /**
     * @notice Permite a cualquier usuario depositar tokens ERC20 en el vault
     * @dev Flujo:
     *      1. Usuario debe haber dado approve previo al vault
     *      2. Se transfieren tokens del usuario al vault usando safeTransferFrom
     *      3. Se genera un depositId único basado en parámetros on-chain
     *      4. Se emite evento Deposit para que el backend acredite el balance
     *
     * Protecciones:
     * - whenNotPaused: no se puede depositar si el contrato está pausado
     * - nonReentrant: previene ataques de reentrancia
     *
     * @param token Dirección del token ERC20 a depositar
     * @param amount Cantidad de tokens a depositar
     * @param recipient Dirección del beneficiario (puede ser distinto al sender)
     * @return depositId Hash único que identifica este depósito
     */
    function depositToken(
        address token,
        uint256 amount,
        address recipient
    ) external whenNotPaused nonReentrant returns (bytes32 depositId) {
        require(token != address(0), "token=0");
        require(recipient != address(0), "recipient=0");
        require(amount > 0, "amount=0");

        // safeTransferFrom protege contra tokens que no retornan bool
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        // Genera ID único usando datos on-chain deterministas
        // El hash garantiza unicidad incluso para múltiples depósitos del mismo usuario
        depositId = keccak256(
            abi.encodePacked(
                block.chainid, // Previene replay cross-chain
                address(this), // Dirección del vault
                token, // Token depositado
                msg.sender, // Quien deposita
                recipient, // Quien recibe el crédito
                amount, // Cantidad
                block.number // Garantiza unicidad temporal
            )
        );

        emit Deposit(token, msg.sender, recipient, amount, depositId);
    }

    // ============================================
    // FUNCIONES PÚBLICAS - RETIROS
    // ============================================

    /**
     * @notice Permite a un usuario solicitar un retiro de tokens
     * @dev Esta función NO ejecuta el retiro, solo emite la solicitud
     *      El backend debe:
     *      1. Escuchar el evento WithdrawalRequested
     *      2. Validar que el usuario tenga balance suficiente off-chain
     *      3. Aplicar controles de riesgo (límites, rate limiting, etc.)
     *      4. Si aprueba, llamar a withdrawToken() desde un operador
     *
     * @param token Token que se desea retirar
     * @param amount Cantidad a retirar
     * @param to Dirección destino que recibirá los tokens
     * @return withdrawalId Hash único de la solicitud de retiro
     */
    function requestWithdraw(
        address token,
        uint256 amount,
        address to
    ) external whenNotPaused returns (bytes32 withdrawalId) {
        require(token != address(0), "token=0");
        require(to != address(0), "to=0");
        require(amount > 0, "amount=0");

        // Genera ID único para la solicitud de retiro
        withdrawalId = keccak256(
            abi.encodePacked(
                block.chainid,
                address(this),
                token,
                msg.sender,
                to,
                amount,
                block.timestamp // Usa timestamp para solicitudes
            )
        );

        emit WithdrawalRequested(token, msg.sender, to, amount, withdrawalId);
    }

    /**
     * @notice Ejecuta un retiro aprobado (solo operadores autorizados)
     * @dev Esta función SOLO puede ser llamada por addresses con OPERATOR_ROLE
     *      El operador (típicamente un servicio backend) debe:
     *      1. Haber validado el retiro off-chain
     *      2. Haber verificado balance del usuario en el ledger
     *      3. Haber aplicado controles de riesgo
     *      4. Pasar el withdrawalId correcto para tracking
     *
     * Protecciones:
     * - onlyRole(OPERATOR_ROLE): solo operadores autorizados
     * - whenNotPaused: no se puede retirar si está pausado
     * - nonReentrant: previene ataques de reentrancia
     *
     * @param token Token a retirar
     * @param amount Cantidad a transferir
     * @param to Dirección que recibirá los tokens
     * @param withdrawalId ID del retiro (debe corresponder a una solicitud previa)
     */
    function withdrawToken(
        address token,
        uint256 amount,
        address to,
        bytes32 withdrawalId
    ) external whenNotPaused nonReentrant onlyRole(OPERATOR_ROLE) {
        require(token != address(0), "token=0");
        require(to != address(0), "to=0");
        require(amount > 0, "amount=0");
        require(withdrawalId != bytes32(0), "wid=0");

        // safeTransfer protege contra tokens que no retornan bool correctamente
        IERC20(token).safeTransfer(to, amount);

        emit WithdrawalExecuted(token, msg.sender, to, amount, withdrawalId);
    }

    // ============================================
    // FUNCIONES DE ADMINISTRACIÓN
    // ============================================

    /**
     * @notice Pausa todas las operaciones del contrato (solo admin)
     * @dev Útil en caso de:
     *      - Detección de vulnerabilidad
     *      - Mantenimiento de emergencia
     *      - Ataque en curso
     *
     *      Cuando está pausado, no se pueden hacer depósitos ni retiros
     */
    function pause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Reanuda las operaciones del contrato (solo admin)
     * @dev Se usa después de resolver el problema que causó la pausa
     */
    function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Otorga el rol de operador a una dirección (solo admin)
     * @dev Los operadores pueden ejecutar retiros aprobados
     *      Típicamente se asigna a:
     *      - Wallets calientes del backend
     *      - Servicios automatizados de retiro
     *      - Multisigs de confianza
     *
     * @param operator Dirección que recibirá privilegios de operador
     */
    function grantOperator(
        address operator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(operator != address(0), "operator=0");
        _grantRole(OPERATOR_ROLE, operator);
    }

    /**
     * @notice Revoca el rol de operador de una dirección (solo admin)
     * @dev Útil cuando:
     *      - Una wallet fue comprometida
     *      - Se necesita rotar operadores
     *      - Un servicio fue deshabilitado
     *
     * @param operator Dirección a la que se le revocará el rol
     */
    function revokeOperator(
        address operator
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(OPERATOR_ROLE, operator);
    }
}
