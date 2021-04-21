// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import "../../interfaces/reflexer/ITaxCollector.sol";
import "../../interfaces/reflexer/ICoinJoin.sol";
import "../../utils/TokenUtils.sol";
import "../ActionBase.sol";
import "./helpers/ReflexerHelper.sol";

/// @title Generate rai from a Reflexer Safe
contract ReflexerGenerate is ActionBase, ReflexerHelper {
    using TokenUtils for address;

    address public constant TAX_COLLECTOR_ADDRESS = 0xcDB05aEda142a1B0D6044C09C64e4226c1a281EB;

    /// @inheritdoc ActionBase
    function executeAction(
        bytes[] memory _callData,
        bytes[] memory _subData,
        uint8[] memory _paramMapping,
        bytes32[] memory _returnValues
    ) public payable override returns (bytes32) {
        (uint256 safeId, uint256 amount, address to) = parseInputs(_callData);

        safeId = _parseParamUint(safeId, _paramMapping[0], _subData, _returnValues);
        amount = _parseParamUint(amount, _paramMapping[1], _subData, _returnValues);
        to = _parseParamAddr(to, _paramMapping[2], _subData, _returnValues);

        amount = _reflexerGenerate(safeId, amount, to);

        return bytes32(amount);
    }

    /// @inheritdoc ActionBase
    function executeActionDirect(bytes[] memory _callData) public payable override {
        (uint256 safeId, uint256 amount, address to) = parseInputs(_callData);

        _reflexerGenerate(safeId, amount, to);
    }

    /// @inheritdoc ActionBase
    function actionType() public pure override returns (uint8) {
        return uint8(ActionType.STANDARD_ACTION);
    }

    //////////////////////////// ACTION LOGIC ////////////////////////////

    /// @notice Generates rai from a specified safe
    /// @param _safeId Id of the safe
    /// @param _amount Amount of rai to be generated
    /// @param _to Address which will receive the rai
    function _reflexerGenerate(
        uint256 _safeId,
        uint256 _amount,
        address _to
    ) internal returns (uint256) {
        address safe = safeManager.safes(_safeId);
        bytes32 collType = safeManager.collateralTypes(_safeId);

        // Generate rai and move to proxy balance
        safeManager.modifySAFECollateralization(
            _safeId,
            int256(0),
            _getGeneratedDeltaDebt(TAX_COLLECTOR_ADDRESS, safe, collType, _amount)
        );
        safeManager.transferInternalCoins(_safeId, address(this), toRad(_amount));

        // add auth so we can exit the rai
        if (safeEngine.safeRights(address(this), address(RAI_ADAPTER_ADDRESS)) == 0) {
            safeEngine.approveSAFEModification(RAI_ADAPTER_ADDRESS);
        }

        // exit rai from adapter and send _to if needed
        ICoinJoin(RAI_ADAPTER_ADDRESS).exit(_to, _amount);

        logger.Log(
            address(this),
            msg.sender,
            "ReflexerGenerate",
            abi.encode(_safeId, _amount, _to)
        );

        return _amount;
    }

    function parseInputs(bytes[] memory _callData)
        internal
        pure
        returns (
            uint256 safeId,
            uint256 amount,
            address to
        )
    {
        safeId = abi.decode(_callData[0], (uint256));
        amount = abi.decode(_callData[1], (uint256));
        to = abi.decode(_callData[2], (address));
    }

    /// @notice Gets delta debt generated (Total Safe debt minus available safeHandler COIN balance)
    /// @param taxCollector address
    /// @param safeHandler address
    /// @param collateralType bytes32
    /// @return deltaDebt
    function _getGeneratedDeltaDebt(
        address taxCollector,
        address safeHandler,
        bytes32 collateralType,
        uint256 wad
    ) internal returns (int256 deltaDebt) {
        // Updates stability fee rate
        uint256 rate = ITaxCollector(taxCollector).taxSingle(collateralType);
        require(rate > 0, "invalid-collateral-type");

        // Gets COIN balance of the handler in the safeEngine
        uint256 coin = safeEngine.coinBalance(safeHandler);

        // If there was already enough COIN in the safeEngine balance, just exits it without adding more debt
        if (coin < mul(wad, RAY)) {
            // Calculates the needed deltaDebt so together with the existing coins in the safeEngine is enough to exit wad amount of COIN tokens
            deltaDebt = toPositiveInt(sub(mul(wad, RAY), coin) / rate);
            // This is neeeded due lack of precision. It might need to sum an extra deltaDebt wei (for the given COIN wad amount)
            deltaDebt = mul(uint256(deltaDebt), rate) < mul(wad, RAY) ? deltaDebt + 1 : deltaDebt;
        }
    }
}
