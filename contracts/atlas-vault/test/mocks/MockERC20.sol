// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ERC20: Implementación estándar de OpenZeppelin de un token ERC20
// Incluye todas las funciones básicas: transfer, approve, balanceOf, etc.
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20
 * @notice Token ERC20 de prueba para usar en tests
 * @dev Este contrato es un mock (simulación) de un token real
 *      Se usa exclusivamente para testing, NO para producción
 *
 *      Características:
 *      - Hereda toda la funcionalidad ERC20 estándar
 *      - Permite mintear tokens libremente (útil para tests)
 *      - No tiene restricciones de supply ni permisos
 *      - Simplifica la creación de escenarios de prueba
 */
contract MockERC20 is ERC20 {
    /**
     * @notice Constructor del token mock
     * @dev Inicializa el token con un nombre y símbolo
     *      No mintea supply inicial (se hace bajo demanda en tests)
     *
     * @param n Nombre del token (ej: "Mock Token")
     * @param s Símbolo del token (ej: "MOCK")
     */
    constructor(string memory n, string memory s) ERC20(n, s) {}

    /**
     * @notice Mintea (crea) tokens para una dirección específica
     * @dev Función pública sin restricciones (solo para testing)
     *      En un token real, esta función tendría:
     *      - Control de acceso (onlyOwner, onlyMinter, etc.)
     *      - Límites de supply máximo
     *      - Validaciones adicionales
     *
     *      Aquí está abierta para facilitar la creación de escenarios de prueba
     *
     * @param to Dirección que recibirá los tokens
     * @param amount Cantidad de tokens a mintear
     */
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
