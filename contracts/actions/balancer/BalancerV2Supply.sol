// SPDX-License-Identifier: MIT

pragma solidity =0.7.6;
pragma experimental ABIEncoderV2;

import "../ActionBase.sol";
import "../../utils/TokenUtils.sol";
import "../../interfaces/balancer/IVault.sol";
import "../../DS/DSMath.sol";
import "hardhat/console.sol";

contract BalancerV2Supply is ActionBase, DSMath {
    using TokenUtils for address;

    IVault public constant vault = IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    struct Params {
        bytes32 poolId;
        address from;
        address to;
        IAsset[] tokens;
        uint256[] maxAmountsIn;
        bytes userData;
    }

    /// @inheritdoc ActionBase
    function executeAction(
        bytes[] memory _callData,
        bytes[] memory _subData,
        uint8[] memory _paramMapping,
        bytes32[] memory _returnValues
    ) public payable virtual override returns (bytes32) {
        Params memory inputData = parseInputs(_callData);

        inputData.from = _parseParamAddr(inputData.from, _paramMapping[0], _subData, _returnValues);
        inputData.to = _parseParamAddr(inputData.to, _paramMapping[1], _subData, _returnValues);

        uint256 poolLPTokensReceived = _balancerSupply(inputData);
        console.log(poolLPTokensReceived);
        return bytes32(poolLPTokensReceived);
    }

    /// @inheritdoc ActionBase
    function executeActionDirect(bytes[] memory _callData) public payable override {
        Params memory inputData = parseInputs(_callData);

        _balancerSupply(inputData);
    }

    /// @inheritdoc ActionBase
    function actionType() public pure virtual override returns (uint8) {
        return uint8(ActionType.STANDARD_ACTION);
    }

    //////////////////////////// ACTION LOGIC ////////////////////////////

    function _balancerSupply(Params memory _inputData) internal returns (uint256 poolLPTokensReceived) {
        address poolAddress = _getPoolAddress(_inputData.poolId);
        uint256 poolLPTokensBefore = poolAddress.getBalance(_inputData.to);

        uint256[] memory tokenBalancesBefore = new uint256[](_inputData.tokens.length);
        for (uint256 i = 0; i < tokenBalancesBefore.length; i++) {
            tokenBalancesBefore[i] = address(_inputData.tokens[i]).getBalance(address(this));
            console.log(tokenBalancesBefore[i]);
        }
        
        _prepareTokensForPoolJoin(_inputData);

        IVault.JoinPoolRequest memory requestData = IVault.JoinPoolRequest(
            _inputData.tokens,
            _inputData.maxAmountsIn,
            _inputData.userData,
            false
        );
        vault.joinPool(_inputData.poolId, address(this), _inputData.to, requestData);


        for (uint256 i = 0; i < tokenBalancesBefore.length; i++) {
            tokenBalancesBefore[i] = sub(
                address(_inputData.tokens[i]).getBalance(address(this)),
                tokenBalancesBefore[i]
            );
            // sending leftovers back
            console.log(tokenBalancesBefore[i]);
            address(_inputData.tokens[i]).withdrawTokens(_inputData.from, tokenBalancesBefore[i]);
        }

        uint256 poolLPTokensAfter = poolAddress.getBalance(_inputData.to);
        poolLPTokensReceived = sub(poolLPTokensAfter, poolLPTokensBefore);

        logger.Log(
            address(this),
            msg.sender,
            "BalancerV2Supply",
            abi.encode(_inputData, tokenBalancesBefore, poolLPTokensReceived)
        );
        console.log(poolLPTokensReceived);
    }

    function _prepareTokensForPoolJoin(Params memory _inputData) internal {
        for (uint256 i = 0; i < _inputData.tokens.length; i++) {
            // pull tokens to proxy and write how many are pulled
            _inputData.maxAmountsIn[i] = address(_inputData.tokens[i]).pullTokensIfNeeded(
                _inputData.from,
                _inputData.maxAmountsIn[i]
            );
            // approve vault so it can pull tokens
            address(_inputData.tokens[i]).approveToken(address(vault), _inputData.maxAmountsIn[i]);
            console.log(_inputData.maxAmountsIn[i]);
        }
    }
    
    function _getPoolAddress(bytes32 poolId) internal pure returns (address) {
        // 12 byte logical shift left to remove the nonce and specialization setting. We don't need to mask,
        // since the logical shift already sets the upper bits to zero.
        return address(uint256(poolId) >> (12 * 8));
    }

    function parseInputs(bytes[] memory _callData) internal pure returns (Params memory inputData) {
        inputData = abi.decode(_callData[0], (Params));
    }
}
