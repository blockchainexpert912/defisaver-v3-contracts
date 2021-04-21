// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import "../../interfaces/reflexer/ICoinJoin.sol";
import "../../utils/TokenUtils.sol";
import "../ActionBase.sol";
import "./helpers/ReflexerHelper.sol";

/// @title Payback rai debt for a reflexer safe
contract ReflexerPayback is ActionBase, ReflexerHelper {
    using TokenUtils for address;

    /// @inheritdoc ActionBase
    function executeAction(
        bytes[] memory _callData,
        bytes[] memory _subData,
        uint8[] memory _paramMapping,
        bytes32[] memory _returnValues
    ) public payable override returns (bytes32) {
        (uint256 safeId, uint256 amount, address from) = parseInputs(_callData);

        safeId = _parseParamUint(safeId, _paramMapping[0], _subData, _returnValues);
        amount = _parseParamUint(amount, _paramMapping[1], _subData, _returnValues);
        from = _parseParamAddr(from, _paramMapping[2], _subData, _returnValues);

        amount = _reflexerPayback(safeId, amount, from);

        return bytes32(amount);
    }

    /// @inheritdoc ActionBase
    function executeActionDirect(bytes[] memory _callData) public payable override {
        (uint256 safeId, uint256 amount, address from) = parseInputs(_callData);

        _reflexerPayback(safeId, amount, from);
    }

    /// @inheritdoc ActionBase
    function actionType() public pure override returns (uint8) {
        return uint8(ActionType.STANDARD_ACTION);
    }

    //////////////////////////// ACTION LOGIC ////////////////////////////

    /// @notice Paybacks the debt for a specified safe
    /// @param _safeId Id of the safe
    /// @param _amount Amount of rai to be payed back
    /// @param _from Where the rai is pulled from
    function _reflexerPayback(
        uint256 _safeId,
        uint256 _amount,
        address _from
    ) internal returns (uint256) {
        address safe = safeManager.safes(_safeId);
        bytes32 collType = safeManager.collateralTypes(_safeId);

        // if amount type(uint256).max payback the whole safe debt
        if (_amount == type(uint256).max) {
            _amount = getAllDebt(safe, safe, collType);
        }

        // pull rai from user and join the reflexer pool
        RAI_ADDRESS.pullTokensIfNeeded(_from, _amount);
        RAI_ADDRESS.approveToken(RAI_ADAPTER_ADDRESS, _amount);
        ICoinJoin(RAI_ADAPTER_ADDRESS).join(safe, _amount);

        int256 paybackAmount =
            _getRepaidDeltaDebt(ISAFEEngine(safeEngine).coinBalance(safe), safe, collType);

        // decrease the safe debt
        safeManager.modifySAFECollateralization(_safeId, 0, paybackAmount);

        logger.Log(
            address(this),
            msg.sender,
            "ReflexerPayback",
            abi.encode(_safeId, _amount, _from)
        );

        return _amount;
    }

    function parseInputs(bytes[] memory _callData)
        internal
        pure
        returns (
            uint256 safeId,
            uint256 amount,
            address from
        )
    {
        safeId = abi.decode(_callData[0], (uint256));
        amount = abi.decode(_callData[1], (uint256));
        from = abi.decode(_callData[2], (address));
    }

    /// @notice Gets repaid delta debt generated (rate adjusted debt)
    /// @param coin uint amount
    /// @param safe uint - safeId
    /// @param collateralType bytes32
    /// @return deltaDebt
    function _getRepaidDeltaDebt(
        uint256 coin,
        address safe,
        bytes32 collateralType
    ) internal view returns (int256 deltaDebt) {
        // Gets actual rate from the safeEngine
        (, uint256 rate, , , , ) = safeEngine.collateralTypes(collateralType);
        require(rate > 0, "invalid-collateral-type");

        // Gets actual generatedDebt value of the safe
        (, uint256 generatedDebt) = safeEngine.safes(collateralType, safe);

        // Uses the whole coin balance in the safeEngine to reduce the debt
        deltaDebt = toPositiveInt(coin / rate);
        // Checks the calculated deltaDebt is not higher than safe.generatedDebt (total debt), otherwise uses its value
        deltaDebt = uint256(deltaDebt) <= generatedDebt
            ? -deltaDebt
            : -toPositiveInt(generatedDebt);
    }

    /// @notice Gets the whole debt of the Safe
    /// @param _usr Address of the Rai holder
    /// @param _urn Urn of the Safe
    /// @param _collType CollType of the Safe
    function getAllDebt(
        address _usr,
        address _urn,
        bytes32 _collType
    ) internal view returns (uint256 raiAmount) {
        (, uint256 rate, , , , ) = safeEngine.collateralTypes(_collType);
        (, uint256 art) = safeEngine.safes(_collType, _urn);
        uint256 rai = safeEngine.coinBalance(_usr);

        uint256 rad = sub(mul(art, rate), rai);
        raiAmount = rad / RAY;

        raiAmount = mul(raiAmount, RAY) < rad ? raiAmount + 1 : raiAmount;
    }
}
