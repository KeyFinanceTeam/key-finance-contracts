// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.8.19;

interface IRewardRouter {
    function gmx() external view returns (address);
    function esGmx() external view returns (address);
    function glp() external view returns (address);
    function weth() external view returns (address);
    function bnGmx() external view returns (address);

    function stakedGmxTracker() external view returns (address);
    function bonusGmxTracker() external view returns (address);
    function feeGmxTracker() external view returns (address);
    function stakedGlpTracker() external view returns (address);
    function feeGlpTracker() external view returns (address);
    function gmxVester() external view returns (address);
    function glpVester() external view returns (address);

    function stakeEsGmx(uint256 _amount) external;
    
    function signalTransfer(address _receiver) external;
    function acceptTransfer(address _sender) external;

    function handleRewards(
        bool _shouldClaimGmx,
        bool _shouldStakeGmx,
        bool _shouldClaimEsGmx,
        bool _shouldStakeEsGmx,
        bool _shouldStakeMultiplierPoints,
        bool _shouldClaimWeth,
        bool _shouldConvertWethToEth
    ) external;

    function mintAndStakeGlpETH(uint256 _minUsdg, uint256 _minGlp) external payable returns (uint256);
    function unstakeAndRedeemGlp(address _tokenOut, uint256 _glpAmount, uint256 _minOut, address _receiver) external returns (uint256);
    function unstakeAndRedeemGlpETH(uint256 _glpAmount, uint256 _minOut, address payable _receiver) external returns (uint256);

    function claim() external;
    function pendingReceivers(address _account) external view returns (address);
}

