// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract CommitmentService {
    // 状态变量
    address public client;                 // 客户的地址
    uint256 public n;                      // 提交的数字和服务提供者的数量
    uint256 public t;                      // 允许失败的最大数量
    uint256 public commitEndTime;          // 提交阶段结束的时间
    uint256 public revealEndTime;          // 客户公开已提交元组的截止时间
    uint256 public lockedAmount;           // 客户锁定的资金
    bool public revealed;                  // 客户是否公开了已提交的元组

    uint256 public g;                      // 群的生成元
    uint256 public e;                      // 客户公开的e值

    // 承诺的元组：每个元组包含一个群元素h和一个承诺commit c
    struct Tuple {
        uint256 h;      // 群上的元素h
        bytes32 c;      // 承诺的commit（哈希值）
    }

    Tuple[] public tuples;                 // 客户承诺的n个元组
    address[] public servers;              // n个服务提供者的地址

    // 提交的ai, bi
    struct Submission {
        uint256 ai;
        uint256 bi;
        bool submitted;
    }

    mapping(address => Submission) public submissions; // 每个服务提供者提交的ai, bi
    uint256 public submissionCount;                    // 已提交的服务提供者数量

    // 事件
    event Commit(address indexed client, address[] servers, uint256 amountLocked);
    event Submit(address indexed server, uint256 ai, uint256 bi);
    event Reveal(address indexed client, uint256 e);
    event DistributeFunds(uint256 successCount, uint256 amountPerWinner);
    event RefundClient(uint256 amount);
    event TimeoutDistribute(uint256 amountPerServer);
    event RevealFailed(address indexed client, string message);

    // 修饰符
    modifier onlyClient() {
        require(msg.sender == client, unicode"不是客户");
        _;
    }

    modifier onlyDuringCommitPhase() {
        require(block.timestamp <= commitEndTime, unicode"提交阶段已结束");
        _;
    }

    modifier onlyDuringRevealPhase() {
        require(block.timestamp > commitEndTime && block.timestamp <= revealEndTime, unicode"不在公开阶段");
        _;
    }

    modifier afterRevealPhase() {
        require(block.timestamp > revealEndTime, unicode"公开阶段尚未结束");
        _;
    }

    constructor(
        uint256 _n,
        uint256 _t,
        uint256 _commitDuration,
        uint256 _revealDuration,
        uint256 _g,                 // 群的生成元g
        Tuple[] memory _tuples,     // Memory数组，含n个元组
        address[] memory _servers
    ) payable {
        require(_n == _tuples.length && _n == _servers.length, unicode"元组或服务提供者数量无效");
        require(msg.value > 0, unicode"必须锁定一些资金");

        client = msg.sender;
        n = _n;
        t = _t;
        g = _g;  // 设置群的生成元g
        commitEndTime = block.timestamp + _commitDuration;
        revealEndTime = commitEndTime + _revealDuration;
        
        // 将memory中的_tuples逐个复制到storage中的tuples
        for (uint256 i = 0; i < _tuples.length; i++) {
            tuples.push(Tuple({
                h: _tuples[i].h,
                c: _tuples[i].c
            }));
        }

        servers = _servers;
        lockedAmount = msg.value;

        emit Commit(client, servers, msg.value);
    }

    // 服务提供者提交他们的ai和bi
    function submit(uint256 _ai, uint256 _bi) external {
        require(block.timestamp <= commitEndTime, unicode"提交阶段已结束");
        require(submissions[msg.sender].submitted == false, unicode"已提交过");

        // 验证提交者是否是有效服务提供者
        bool isValidServer = false;
        for (uint256 i = 0; i < servers.length; i++) {
            if (servers[i] == msg.sender) {
                isValidServer = true;
                break;
            }
        }
        require(isValidServer, unicode"不是有效服务提供者");

        submissions[msg.sender] = Submission(_ai, _bi, true);
        submissionCount++;

        emit Submit(msg.sender, _ai, _bi);
    }

    // 客户公开之前承诺的e值
    function reveal(uint256 _e) external onlyClient onlyDuringRevealPhase {
        e = _e;
        revealed = true;

        emit Reveal(client, _e);

        // 评估提交情况并进行资金分配
        _evaluateSubmissions();
    }

    // 评估所有服务提供者的提交，并决定资金分配或退款
    function _evaluateSubmissions() internal {
        uint256 successCount = 0;
        uint256 failCount = 0;

        for (uint256 i = 0; i < n; i++) {
            address server = servers[i];
            Submission memory submission = submissions[server];
            Tuple memory tuple = tuples[i];

            // 如果服务提供者未提交，默认提交(0, 0)
            if (!submission.submitted) {
                submission = Submission(0, 0, true);
            }

            // 验证g^(b_i - e * a_i) 是否等于 h_i
            if (_powMod(g, submission.bi - e * submission.ai) == tuple.h) {
                successCount++;
            } else {
                failCount++;
            }
        }

        // 分配资金或退款
        if (failCount <= t) {
            uint256 amountPerWinner = lockedAmount / successCount;
            for (uint256 i = 0; i < n; i++) {
                address server = servers[i];
                Submission memory submission = submissions[server];
                Tuple memory tuple = tuples[i];
                if (_powMod(g, submission.bi - e * submission.ai) == tuple.h) {
                    payable(server).transfer(amountPerWinner);
                }
            }
            emit DistributeFunds(successCount, amountPerWinner);
        } else {
            payable(client).transfer(lockedAmount); // 如果失败数量超过阈值，退款给客户
            emit RefundClient(lockedAmount);
        }
    }

    // 用于计算群的指数运算（g^x mod p）
    function _powMod(uint256 base, uint256 exponent) internal pure returns (uint256) {
        return base ** exponent;  // 在此处假设使用一个安全的大整数库或实现
    }

    // 如果客户未能按时公开，平分资金给所有服务提供者
    function distributeIfNotRevealed() external afterRevealPhase {
        require(!revealed, unicode"已公开");

        uint256 amountPerServer = lockedAmount / n;
        for (uint256 i = 0; i < n; i++) {
            payable(servers[i]).transfer(amountPerServer);
        }

        emit TimeoutDistribute(amountPerServer);
    }
}