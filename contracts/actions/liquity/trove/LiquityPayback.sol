// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import "../helpers/LiquityHelper.sol";
import "../../../utils/TokenUtils.sol";
import "../../ActionBase.sol";

contract LiquityPayback is ActionBase, LiquityHelper {
    using TokenUtils for address;

    struct Params {
        uint256 lusdAmount; // Amount of LUSD tokens to repay
        address from;       // Address where to pull the tokens from
        address upperHint;
        address lowerHint;
    }

    /// @inheritdoc ActionBase
    function executeAction(
        bytes[] memory _callData,
        bytes[] memory _subData,
        uint8[] memory _paramMapping,
        bytes32[] memory _returnValues
    ) public payable virtual override returns (bytes32) {
        Params memory params = parseInputs(_callData);

        params.lusdAmount = _parseParamUint(
            params.lusdAmount,
            _paramMapping[0],
            _subData,
            _returnValues
        );
        params.from = _parseParamAddr(params.from, _paramMapping[1], _subData, _returnValues);

        params.lusdAmount = _liquityPayback(params);
        return bytes32(params.lusdAmount);
    }

    /// @inheritdoc ActionBase
    function executeActionDirect(bytes[] memory _callData) public payable virtual override {
        Params memory params = parseInputs(_callData);

        _liquityPayback(params);
    }

    /// @inheritdoc ActionBase
    function actionType() public pure virtual override returns (uint8) {
        return uint8(ActionType.STANDARD_ACTION);
    }

    //////////////////////////// ACTION LOGIC ////////////////////////////

    /// @notice Repays LUSD tokens to the trove
    function _liquityPayback(Params memory _params) internal returns (uint256) {
        LUSDTokenAddr.pullTokensIfNeeded(_params.from, _params.lusdAmount);

        BorrowerOperations.repayLUSD(_params.lusdAmount, _params.upperHint, _params.lowerHint);

        logger.Log(
            address(this),
            msg.sender,
            "LiquityPayback",
            abi.encode(_params.lusdAmount, _params.from)
        );

        return _params.lusdAmount;
    }

    function parseInputs(bytes[] memory _callData) internal pure returns (Params memory params) {
        params = abi.decode(_callData[0], (Params));
    }
}
