// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import "../../ActionBase.sol";
import "../helpers/CurveHelper.sol";
import "../../../utils/TokenUtils.sol";

import "../../../interfaces/curve/ILiquidityGauge.sol";

contract CurveGaugeWithdraw is ActionBase, CurveHelper {
    using TokenUtils for address;

    struct Params {
        address gaugeAddr;
        address receiver;
        uint256 amount;
    }

    function executeAction(
        bytes[] memory _callData,
        bytes[] memory _subData,
        uint8[] memory _paramMapping,
        bytes32[] memory _returnValues
    ) public payable virtual override returns (bytes32) {
        Params memory params = parseInputs(_callData);
        params.receiver = _parseParamAddr(params.receiver, _paramMapping[1], _subData, _returnValues);
        params.amount = _parseParamUint(params.amount, _paramMapping[2], _subData, _returnValues);

        uint256 withdrawn = _curveGaugeWithdraw(params);
        return bytes32(withdrawn);
    }

    /// @inheritdoc ActionBase
    function executeActionDirect(bytes[] memory _callData) public payable virtual override {
        Params memory params = parseInputs(_callData);
        _curveGaugeWithdraw(params);
    }

    /// @inheritdoc ActionBase
    function actionType() public pure virtual override returns (uint8) {
        return uint8(ActionType.STANDARD_ACTION);
    }

    /// @notice Dont forget NatSpec
    function _curveGaugeWithdraw(Params memory _params) internal returns (uint256) {
        require(_params.receiver != address(0), "receiver cant be 0x0");
        // if _params.receiver != address(this) the receiver must call set_approve_deposit on gauge
        if (_params.amount == type(uint256).max) {
            _params.amount = ILiquidityGauge(_params.gaugeAddr).balanceOf(address(this));
        }

        ILiquidityGauge(_params.gaugeAddr).withdraw(_params.amount);
        address lpToken = ILiquidityGauge(_params.gaugeAddr).lp_token();
        lpToken.withdrawTokens(_params.receiver, _params.amount);

        logger.Log(
            address(this),
            msg.sender,
            "CurveGaugeWithdraw",
            abi.encode(
                _params
            )
        );

        return _params.amount;
    }

    function parseInputs(bytes[] memory _callData) internal pure returns (Params memory params) {
        params = abi.decode(_callData[0], (Params));
    }
}