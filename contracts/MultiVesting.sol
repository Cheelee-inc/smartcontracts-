// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IVesting.sol";

contract MultiVesting is IVesting, Ownable {
    using SafeERC20 for IERC20;

    event SetSeller(address newSeller);
    event Vested(address beneficiary, uint256 amount);
    event EmergencyVest(uint256 amount);

    IERC20 public immutable token;
    address public seller;

    mapping(address => uint256) public released;

    mapping(address => Beneficiary) public beneficiary;

    constructor(IERC20 _token) {
        require(address(_token) != address(0), "Can't set zero address");
        token = _token;
    }

    function setSeller(address _addr) external onlyOwner {
        require(_addr != address(0), "Can't set zero address");
        seller = _addr;

        emit SetSeller(seller);
    }

    /**
        _cliff = duration in seconds
        _duration = duration in seconds
        _startTimestamp = timestamp
    */
    function vest(
        address _beneficiaryAddress,
        uint256 _startTimestamp,
        uint256 _durationSeconds,
        uint256 _amount,
        uint256 _cliff
    ) external override {
        require(msg.sender == seller, "Only sale contract can call");
        require(
            _beneficiaryAddress != address(0),
            "beneficiary is zero address"
        );

        require(_durationSeconds > 0, "Duration must be above 0");

        beneficiary[_beneficiaryAddress].start = _startTimestamp;
        beneficiary[_beneficiaryAddress].duration = _durationSeconds;
        beneficiary[_beneficiaryAddress].cliff = _cliff;
        beneficiary[_beneficiaryAddress].amount += _amount;

        emit Vested(_beneficiaryAddress, _amount);
    }

    function release(address _beneficiaryAddress) external override {
        (uint256 _releasableAmount, ) = _releasable(
            msg.sender,
            block.timestamp
        );

        require(_releasableAmount > 0, "Can't claim yet!");

        released[_beneficiaryAddress] += _releasableAmount;
        token.safeTransfer(_beneficiaryAddress, _releasableAmount);

        emit Released(_releasableAmount, msg.sender);
    }

    function releasable(address _beneficiary, uint256 _timestamp)
        external
        view
        override
        returns (uint256 canClaim, uint256 earnedAmount)
    {
        return _releasable(_beneficiary, _timestamp);
    }

    function _releasable(address _beneficiary, uint256 _timestamp)
        internal
        view
        returns (uint256 canClaim, uint256 earnedAmount)
    {
        (canClaim, earnedAmount) = _vestingSchedule(
            _beneficiary,
            beneficiary[_beneficiary].amount,
            _timestamp
        );
        canClaim -= released[_beneficiary];
    }

    function vestedAmountBeneficiary(address _beneficiary, uint256 _timestamp)
        external
        view
        override
        returns (uint256 vestedAmount, uint256 maxAmount)
    {
        return _vestedAmountBeneficiary(_beneficiary, _timestamp);
    }

    function _vestedAmountBeneficiary(address _beneficiary, uint256 _timestamp)
        internal
        view
        returns (uint256 vestedAmount, uint256 maxAmount)
    {
        // maxAmount = token.balanceOf(address(this)) + _released;
        maxAmount = beneficiary[_beneficiary].amount;
        (, vestedAmount) = _vestingSchedule(
            _beneficiary,
            maxAmount,
            _timestamp
        );
    }

    function _vestingSchedule(
        address _beneficiary,
        uint256 _totalAllocation,
        uint256 _timestamp
    ) internal view returns (uint256, uint256) {
        if (_timestamp < beneficiary[_beneficiary].start) {
            return (0, 0);
        } else if (
            _timestamp >
            beneficiary[_beneficiary].start + beneficiary[_beneficiary].duration
        ) {
            return (_totalAllocation, _totalAllocation);
        } else {
            uint256 res = (_totalAllocation *
                (_timestamp - beneficiary[_beneficiary].start)) /
                beneficiary[_beneficiary].duration;

            if (
                _timestamp <
                beneficiary[_beneficiary].start +
                    beneficiary[_beneficiary].cliff
            ) return (0, res);
            else return (res, res);
        }
    }

    function updateBeneficiary(address _oldBeneficiary, address _newBeneficiary)
        external
    {
        require(
            msg.sender == owner() || msg.sender == _oldBeneficiary,
            "Not allowed to change"
        );

        released[_newBeneficiary] = released[_oldBeneficiary];
        beneficiary[_newBeneficiary] = beneficiary[_oldBeneficiary];

        delete released[_oldBeneficiary];
        delete beneficiary[_oldBeneficiary];
    }

    function emergencyVest(IERC20 _token) external override onlyOwner {
        uint256 amount = _token.balanceOf(address(this));
        _token.safeTransfer(owner(), amount);
        emit EmergencyVest(amount);
    }
}
