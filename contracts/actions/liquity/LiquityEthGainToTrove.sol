// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import "./helpers/LiquityHelper.sol";
import "../../utils/TokenUtils.sol";
import "../../utils/SafeMath.sol";
import "../ActionBase.sol";

contract LiquityEthGainToTrove is ActionBase, LiquityHelper {
    using TokenUtils for address;
    using SafeMath for uint256;

    struct Params {
        address lqtyTo;
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
        params.lqtyTo = _parseParamAddr(params.lqtyTo, _paramMapping[0], _subData, _returnValues);

        uint256 ethGain = _liquityEthGainToTrove(params);
        return bytes32(ethGain);
    }

    /// @inheritdoc ActionBase
    function executeActionDirect(bytes[] memory _callData) public payable virtual override {
        Params memory params = parseInputs(_callData);

        _liquityEthGainToTrove(params);
    }

    /// @inheritdoc ActionBase
    function actionType() public pure virtual override returns (uint8) {
        return uint8(ActionType.STANDARD_ACTION);
    }

    //////////////////////////// ACTION LOGIC ////////////////////////////

    /// @notice dont forget natspec
    function _liquityEthGainToTrove(Params memory _params) internal returns (uint256) {
        uint256 ethGain = StabilityPool.getDepositorETHGain(address(this));
        uint256 lqtyGain = StabilityPool.getDepositorLQTYGain(address(this));
        
        StabilityPool.withdrawETHGainToTrove(_params.upperHint, _params.lowerHint);

        LQTYTokenAddr.withdrawTokens(_params.lqtyTo, lqtyGain);

        logger.Log(
            address(this),
            msg.sender,
            "LiquityEthGainToTrove",
            abi.encode(
                ethGain,
                _params.lqtyTo
            )
        );

        return ethGain;
    }

    function parseInputs(bytes[] memory _callData) internal pure returns (Params memory params) {
        params = abi.decode(_callData[0], (Params));
    }
}
