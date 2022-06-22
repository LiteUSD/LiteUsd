// SPDX-License-Identifier: MIT
pragma solidity 0.8.14;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract IDO is Ownable {
    using EnumerableSet for EnumerableSet.AddressSet;
    using SafeERC20 for IERC20;

    // 是否结束
    bool public isEnded = false;
    // 结束时间
    uint256 public endedAt;
    // 可领取时间
    uint256 public getTokenAt;
    // 报价币种 USDT
    address public immutable usdt;
    // 发行币种
    address public immutable token;
    uint8 public immutable tokenDecimals;
    // 参与数量最小数量
    uint256 public minBuy;
    // 单价, 1 Token = ? USDT
    uint256 public tokenPrice;
    // 总 IDO 数量
    uint256 public tokenSupply;
    // 计算单位
    uint256 constant UNIT = 1e6;
    // 总收 usdt 数量
    uint256 public usdtTotal;
    // 用户投入数量
    mapping(address => uint256) public userTotal;
    // 用户已经领取 Token
    mapping(address => bool) public userDone;
    // 管理员已领取 IDO 代币
    bool public ownerDone = false;
    // 参与用户列表
    EnumerableSet.AddressSet private _users;

    // 参与事件
    event UserBuy(address indexed user, uint256 amount);
    // 领取 Token 事件
    event GetToken(
        address indexed user,
        uint256 tokenAmount,
        uint256 returnUsdtAmount
    );

    constructor(
        address usdt_, // 收取币种
        address token_, // 发行币种
        uint256 tokenPrice_, // 单价, 1 Token = ? USDT
        uint256 minBuy_, // 最小买入量, ? USDT
        uint256 tokenSupply_ // 总发行数量
    ) {
        usdt = usdt_;
        token = token_;
        tokenDecimals = ERC20(token_).decimals();
        tokenPrice = tokenPrice_;
        minBuy = minBuy_;
        tokenSupply = tokenSupply_;
    }

    function setEnd(uint256 getTokenAt_) external onlyOwner {
        require(!isEnded, "Already ended");
        require(
            getTokenAt_ > block.timestamp,
            "getTokenAt must be in the future"
        );
        isEnded = true;
        endedAt = block.timestamp;
        getTokenAt = getTokenAt_;
    }

    function setMinBuy(uint256 amount_) external onlyOwner {
        require(!isEnded, "Already ended");
        minBuy = amount_;
    }

    // 设置 tokenPrice
    function setTokenPrice(uint256 price_) external onlyOwner {
        require(!isEnded, "Already ended");
        require(price_ > 0, "Price must be greater than 0");
        tokenPrice = price_;
    }

    // 设置 tokenSupply
    function setTokenSupply(uint256 supply_) external onlyOwner {
        require(!isEnded, "Already ended");
        require(supply_ > 0, "Supply must be greater than 0");
        tokenSupply = supply_;
    }

    // 用户总数
    function userLength() external view returns (uint256) {
        return _users.length();
    }

    // 用户
    function user(uint256 index_) external view returns (address) {
        return _users.at(index_);
    }

    // 参与 IDO
    function buy(uint256 amount_) external {
        require(
            amount_ >= minBuy,
            "amount must be greater than or equal to minBuy"
        );
        require(!isEnded, "Already ended");

        IERC20(usdt).safeTransferFrom(msg.sender, address(this), amount_);
        userTotal[msg.sender] += amount_;
        usdtTotal += amount_;

        // 添加到用户列表
        if (!_users.contains(msg.sender)) {
            _users.add(msg.sender);
        }

        emit UserBuy(msg.sender, amount_);
    }

    // 用户可获得 Token 数量
    function userAmount(address account_) public view returns (uint256) {
        if (userTotal[account_] == 0) {
            return 0;
        }

        // 可获得 Token 数量(根据份额计算)
        uint256 tokenAmount = (userTotal[account_] * tokenSupply) / usdtTotal;
        // 实际最大获得数量(根据投入 USDT 计算)
        uint256 maxBuyAmount = (userTotal[account_] * 10**tokenDecimals) /
            tokenPrice;

        if (tokenAmount < maxBuyAmount) {
            return tokenAmount;
        } else {
            return maxBuyAmount;
        }
    }

    // 用户取得 Token, 有多余 USDT 也会一并返还
    function getToken() external {
        require(isEnded, "Not ended");
        require(!userDone[msg.sender], "Already got token");
        require(getTokenAt <= block.timestamp, "Not yet");

        uint256 amount = userAmount(msg.sender);
        require(amount > 0, "No token");
        require(
            IERC20(token).balanceOf(address(this)) >= amount,
            "Not enough token"
        );
        IERC20(token).safeTransfer(msg.sender, amount);
        userDone[msg.sender] = true;
        // 返回多余 USDT
        uint256 diff = userTotal[msg.sender] -
            (amount * tokenPrice) /
            10**tokenDecimals;

        if (diff > 0) {
            uint256 balance = IERC20(usdt).balanceOf(address(this));
            if (balance < diff) {
                IERC20(usdt).safeTransfer(msg.sender, balance);
            } else {
                IERC20(usdt).safeTransfer(msg.sender, diff);
            }
        }

        emit GetToken(msg.sender, amount, diff);
    }

    // 管理员取得 IDO 的 USDT
    function getUsdt() external onlyOwner {
        require(isEnded, "Not ended");
        require(!ownerDone, "Already got");
        // 预计总收 USDT
        uint256 sellUsdtAmount = (tokenSupply * tokenPrice) / 10**tokenDecimals;

        if (usdtTotal > sellUsdtAmount) {
            uint256 balance = IERC20(usdt).balanceOf(address(this));
            if (balance < sellUsdtAmount) {
                IERC20(usdt).safeTransfer(owner(), balance);
            } else {
                IERC20(usdt).safeTransfer(owner(), sellUsdtAmount);
            }
        } else {
            IERC20(usdt).safeTransfer(owner(), usdtTotal);
        }

        ownerDone = true;
    }

    // 管理员取得 Token
    function ownerToken(uint256 amount_) external onlyOwner {
        IERC20(token).safeTransfer(owner(), amount_);
    }
}
