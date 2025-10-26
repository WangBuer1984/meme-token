// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title SimpleMemeToken - 简化版Meme代币合约(学习用)
 * @notice 实现了基本的交易税、简单流动性池和交易限制功能
 * @dev 适合初学者学习区块链开发
 */

contract SimpleMemeToken {
    
    // ============ 基本代币信息 ============
    
    string public name = "SimpleMeme";           // 代币名称
    string public symbol = "SMEME";              // 代币符号
    uint8 public decimals = 18;                  // 小数位数
    uint256 public totalSupply = 1000000 * 10**18;  // 总供应量: 100万代币
    
    // ============ 余额和授权映射 ============
    
    // 记录每个地址的代币余额
    mapping(address => uint256) public balanceOf;
    
    // 记录授权额度: balanceOf[owner][spender] = amount
    // owner授权spender可以花费amount数量的代币
    mapping(address => mapping(address => uint256)) public allowance;
    
    // ============ 税费相关变量 ============
    
    // 税费比例(百分比)
    uint256 public buyTaxRate = 5;      // 买入税 5%
    uint256 public sellTaxRate = 8;     // 卖出税 8%
    uint256 public transferTaxRate = 2; // 转账税 2%
    
    // 税费收集地址
    address public feeWallet;           // 接收税费的钱包地址
    uint256 public collectedFees;       // 已收集的税费总额
    
    // ============ 简单流动性池 ============
    
    // 流动性池余额
    uint256 public liquidityTokens;     // 池中的代币数量
    uint256 public liquidityETH;        // 池中的ETH数量
    
    // 流动性提供者(LP)的份额
    mapping(address => uint256) public liquidityShares;  // 每个LP拥有的份额
    uint256 public totalLiquidityShares;                 // 总份额
    
    // ============ 交易限制 ============
    
    // 单笔交易最大额度
    uint256 public maxTxAmount = 10000 * 10**18;  // 1万代币
    
    // 钱包最大持有量
    uint256 public maxWalletAmount = 20000 * 10**18;  // 2万代币
    
    // 每日交易次数限制
    mapping(address => uint256) public dailyTxCount;      // 今日交易次数
    mapping(address => uint256) public lastTxDate;        // 上次交易日期
    uint256 public maxDailyTx = 10;                       // 每日最多10笔交易
    
    // ============ 白名单 ============
    
    // 免税和免限制的地址
    mapping(address => bool) public isExcluded;
    
    // ============ 合约所有者 ============
    
    address public owner;
    
    // ============ 事件定义 ============
    
    // ERC20标准事件
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
    
    // 自定义事件
    event TaxCollected(address indexed from, uint256 amount);
    event LiquidityAdded(address indexed provider, uint256 tokenAmount, uint256 ethAmount, uint256 shares);
    event LiquidityRemoved(address indexed provider, uint256 tokenAmount, uint256 ethAmount, uint256 shares);
    event FeesWithdrawn(address indexed to, uint256 amount);
    
    // ============ 修饰符 ============
    
    // 只有所有者可以调用
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call");
        _;
    }
    
    // ============ 构造函数 ============
    
    /**
     * @notice 初始化代币合约
     * @param _feeWallet 接收税费的钱包地址
     */
    constructor(address _feeWallet) {
        owner = msg.sender;                    // 设置合约部署者为所有者
        feeWallet = _feeWallet;                // 设置税费钱包
        balanceOf[msg.sender] = totalSupply;   // 将所有代币分配给部署者
        isExcluded[msg.sender] = true;         // 所有者加入白名单
        isExcluded[address(this)] = true;      // 合约地址加入白名单
        
        emit Transfer(address(0), msg.sender, totalSupply);
    }
    
    // ============ 核心功能1: 代币转账(包含税费) ============
    
    /**
     * @notice 转账代币给其他地址
     * @param to 接收者地址
     * @param amount 转账数量
     * @return 是否成功
     */
    function transfer(address to, uint256 amount) public returns (bool) {
        return _transfer(msg.sender, to, amount);
    }
    
    /**
     * @notice 从授权额度中转账
     * @param from 发送者地址
     * @param to 接收者地址
     * @param amount 转账数量
     * @return 是否成功
     */
    function transferFrom(address from, address to, uint256 amount) public returns (bool) {
        // 检查授权额度
        require(allowance[from][msg.sender] >= amount, "Allowance not enough");
        
        // 减少授权额度
        allowance[from][msg.sender] -= amount;
        
        // 执行转账
        return _transfer(from, to, amount);
    }
    
    /**
     * @notice 内部转账函数,处理税费和限制逻辑
     * @param from 发送者
     * @param to 接收者
     * @param amount 金额
     */
    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        require(from != address(0), "Transfer from zero address");
        require(to != address(0), "Transfer to zero address");
        require(amount > 0, "Amount must be greater than 0");
        require(balanceOf[from] >= amount, "Balance not enough");
        
        // 检查交易限制(白名单除外)
        if (!isExcluded[from] && !isExcluded[to]) {
            // 检查单笔交易限制
            require(amount <= maxTxAmount, "Exceeds max transaction amount");
            
            // 检查接收者钱包限制
            require(balanceOf[to] + amount <= maxWalletAmount, "Exceeds max wallet amount");
            
            // 检查每日交易次数
            _checkDailyLimit(from);
        }
        
        // 计算税费
        uint256 taxAmount = 0;
        uint256 amountAfterTax = amount;
        
        // 如果不在白名单中,收取税费
        if (!isExcluded[from] && !isExcluded[to]) {
            // 判断交易类型并计算税费
            uint256 taxRate = transferTaxRate;  // 默认转账税
            
            // 这里简化处理,实际项目中会判断是否是从/到流动性池
            
            taxAmount = (amount * taxRate) / 100;
            amountAfterTax = amount - taxAmount;
            
            // 收集税费到合约
            if (taxAmount > 0) {
                balanceOf[address(this)] += taxAmount;
                collectedFees += taxAmount;
                emit TaxCollected(from, taxAmount);
            }
        }
        
        // 执行转账
        balanceOf[from] -= amount;
        balanceOf[to] += amountAfterTax;
        
        emit Transfer(from, to, amountAfterTax);
        return true;
    }
    
    /**
     * @notice 检查每日交易次数限制
     * @param user 用户地址
     */
    function _checkDailyLimit(address user) internal {
        // 获取当前日期(天数)
        uint256 today = block.timestamp / 1 days;
        
        // 如果是新的一天,重置计数
        if (lastTxDate[user] < today) {
            dailyTxCount[user] = 0;
            lastTxDate[user] = today;
        }
        
        // 检查是否超过每日限制
        require(dailyTxCount[user] < maxDailyTx, "Daily transaction limit reached");
        
        // 增加交易次数
        dailyTxCount[user]++;
    }
    
    // ============ 核心功能2: 简单流动性池 ============
    
    /**
     * @notice 添加流动性
     * @dev 用户提供代币和ETH,获得流动性份额
     * @param tokenAmount 提供的代币数量
     */
    function addLiquidity(uint256 tokenAmount) public payable {
        require(tokenAmount > 0, "Token amount must be greater than 0");
        require(msg.value > 0, "ETH amount must be greater than 0");
        require(balanceOf[msg.sender] >= tokenAmount, "Not enough tokens");
        
        uint256 shares = 0;
        
        // 计算应该获得的份额
        if (totalLiquidityShares == 0) {
            // 第一次添加流动性,份额等于提供的代币数量
            shares = tokenAmount;
        } else {
            // 按比例计算份额
            // shares = (tokenAmount * totalShares) / liquidityTokens
            shares = (tokenAmount * totalLiquidityShares) / liquidityTokens;
        }
        
        require(shares > 0, "Shares must be greater than 0");
        
        // 转入代币到合约
        balanceOf[msg.sender] -= tokenAmount;
        balanceOf[address(this)] += tokenAmount;
        
        // 更新流动性池
        liquidityTokens += tokenAmount;
        liquidityETH += msg.value;
        
        // 分配份额给流动性提供者
        liquidityShares[msg.sender] += shares;
        totalLiquidityShares += shares;
        
        emit LiquidityAdded(msg.sender, tokenAmount, msg.value, shares);
        emit Transfer(msg.sender, address(this), tokenAmount);
    }
    
    /**
     * @notice 移除流动性
     * @dev 用户销毁流动性份额,取回代币和ETH
     * @param shares 要移除的份额数量
     */
    function removeLiquidity(uint256 shares) public {
        require(shares > 0, "Shares must be greater than 0");
        require(liquidityShares[msg.sender] >= shares, "Not enough shares");
        require(totalLiquidityShares > 0, "No liquidity");
        
        // 计算可以取回的代币和ETH数量
        uint256 tokenAmount = (shares * liquidityTokens) / totalLiquidityShares;
        uint256 ethAmount = (shares * liquidityETH) / totalLiquidityShares;
        
        require(tokenAmount > 0 && ethAmount > 0, "Amounts must be greater than 0");
        
        // 更新流动性池
        liquidityTokens -= tokenAmount;
        liquidityETH -= ethAmount;
        
        // 销毁份额
        liquidityShares[msg.sender] -= shares;
        totalLiquidityShares -= shares;
        
        // 转出代币和ETH
        balanceOf[address(this)] -= tokenAmount;
        balanceOf[msg.sender] += tokenAmount;
        payable(msg.sender).transfer(ethAmount);
        
        emit LiquidityRemoved(msg.sender, tokenAmount, ethAmount, shares);
        emit Transfer(address(this), msg.sender, tokenAmount);
    }
    
    /**
     * @notice 通过流动性池买入代币
     * @dev 用户发送ETH,从池中获得代币
     */
    function buyTokens() public payable {
        require(msg.value > 0, "Must send ETH");
        require(liquidityTokens > 0 && liquidityETH > 0, "No liquidity");
        
        // 简单的恒定乘积做市商公式: x * y = k
        // tokenAmount = liquidityTokens - (k / (liquidityETH + ethIn))
        uint256 k = liquidityTokens * liquidityETH;
        uint256 newLiquidityETH = liquidityETH + msg.value;
        uint256 newLiquidityTokens = k / newLiquidityETH;
        uint256 tokenAmount = liquidityTokens - newLiquidityTokens;
        
        // 收取买入税
        uint256 tax = (tokenAmount * buyTaxRate) / 100;
        uint256 tokensAfterTax = tokenAmount - tax;
        
        require(tokensAfterTax > 0, "Token amount too small");
        
        // 更新流动性池
        liquidityTokens = newLiquidityTokens;
        liquidityETH = newLiquidityETH;
        
        // 转出代币(扣除税费)
        balanceOf[address(this)] -= tokenAmount;
        balanceOf[msg.sender] += tokensAfterTax;
        collectedFees += tax;
        
        emit Transfer(address(this), msg.sender, tokensAfterTax);
        emit TaxCollected(msg.sender, tax);
    }
    
    /**
     * @notice 通过流动性池卖出代币
     * @dev 用户发送代币,从池中获得ETH
     * @param tokenAmount 要卖出的代币数量
     */
    function sellTokens(uint256 tokenAmount) public {
        require(tokenAmount > 0, "Amount must be greater than 0");
        require(balanceOf[msg.sender] >= tokenAmount, "Not enough tokens");
        require(liquidityTokens > 0 && liquidityETH > 0, "No liquidity");
        
        // 收取卖出税
        uint256 tax = (tokenAmount * sellTaxRate) / 100;
        uint256 tokensAfterTax = tokenAmount - tax;
        
        // 恒定乘积公式计算可获得的ETH
        uint256 k = liquidityTokens * liquidityETH;
        uint256 newLiquidityTokens = liquidityTokens + tokensAfterTax;
        uint256 newLiquidityETH = k / newLiquidityTokens;
        uint256 ethAmount = liquidityETH - newLiquidityETH;
        
        require(ethAmount > 0, "ETH amount too small");
        require(address(this).balance >= ethAmount, "Not enough ETH in pool");
        
        // 更新流动性池
        liquidityTokens = newLiquidityTokens;
        liquidityETH = newLiquidityETH;
        
        // 转入代币(包含税费)
        balanceOf[msg.sender] -= tokenAmount;
        balanceOf[address(this)] += tokenAmount;
        collectedFees += tax;
        
        // 转出ETH
        payable(msg.sender).transfer(ethAmount);
        
        emit Transfer(msg.sender, address(this), tokenAmount);
        emit TaxCollected(msg.sender, tax);
    }
    
    /**
     * @notice 查询代币价格(1个代币值多少ETH)
     * @return 价格(以wei为单位)
     */
    function getTokenPrice() public view returns (uint256) {
        if (liquidityTokens == 0) return 0;
        return (liquidityETH * 10**18) / liquidityTokens;
    }
    
    // ============ 核心功能3: 授权机制 ============
    
    /**
     * @notice 授权其他地址使用自己的代币
     * @param spender 被授权的地址
     * @param amount 授权数量
     * @return 是否成功
     */
    function approve(address spender, uint256 amount) public returns (bool) {
        require(spender != address(0), "Approve to zero address");
        
        allowance[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    
    // ============ 管理员功能 ============
    
    /**
     * @notice 设置税率
     * @param _buyTax 买入税
     * @param _sellTax 卖出税
     * @param _transferTax 转账税
     */
    function setTaxRates(uint256 _buyTax, uint256 _sellTax, uint256 _transferTax) public onlyOwner {
        require(_buyTax <= 20, "Buy tax too high");      // 最高20%
        require(_sellTax <= 20, "Sell tax too high");    // 最高20%
        require(_transferTax <= 10, "Transfer tax too high");  // 最高10%
        
        buyTaxRate = _buyTax;
        sellTaxRate = _sellTax;
        transferTaxRate = _transferTax;
    }
    
    /**
     * @notice 设置交易限制
     * @param _maxTx 单笔最大交易额
     * @param _maxWallet 钱包最大持有量
     */
    function setLimits(uint256 _maxTx, uint256 _maxWallet) public onlyOwner {
        require(_maxTx >= totalSupply / 1000, "Max tx too low");  // 至少0.1%
        require(_maxWallet >= totalSupply / 100, "Max wallet too low");  // 至少1%
        
        maxTxAmount = _maxTx;
        maxWalletAmount = _maxWallet;
    }
    
    /**
     * @notice 设置每日交易次数限制
     * @param _maxDaily 每日最大交易次数
     */
    function setMaxDailyTx(uint256 _maxDaily) public onlyOwner {
        require(_maxDaily >= 5, "Too restrictive");
        maxDailyTx = _maxDaily;
    }
    
    /**
     * @notice 设置白名单
     * @param account 地址
     * @param excluded 是否加入白名单
     */
    function setExcluded(address account, bool excluded) public onlyOwner {
        isExcluded[account] = excluded;
    }
    
    /**
     * @notice 提取收集的税费
     * @dev 将税费发送到税费钱包
     */
    function withdrawFees() public onlyOwner {
        require(collectedFees > 0, "No fees to withdraw");
        
        uint256 amount = collectedFees;
        collectedFees = 0;
        
        balanceOf[address(this)] -= amount;
        balanceOf[feeWallet] += amount;
        
        emit Transfer(address(this), feeWallet, amount);
        emit FeesWithdrawn(feeWallet, amount);
    }
    
    /**
     * @notice 更新税费钱包地址
     * @param newFeeWallet 新的税费钱包地址
     */
    function setFeeWallet(address newFeeWallet) public onlyOwner {
        require(newFeeWallet != address(0), "Invalid address");
        feeWallet = newFeeWallet;
    }
    
    /**
     * @notice 转移所有权
     * @param newOwner 新所有者地址
     */
    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Invalid address");
        owner = newOwner;
    }
    
    // ============ 查询功能 ============
    
    /**
     * @notice 查询用户今日剩余交易次数
     * @param user 用户地址
     * @return 剩余次数
     */
    function getRemainingDailyTx(address user) public view returns (uint256) {
        uint256 today = block.timestamp / 1 days;
        
        if (lastTxDate[user] < today) {
            return maxDailyTx;  // 新的一天,全部次数可用
        }
        
        if (dailyTxCount[user] >= maxDailyTx) {
            return 0;  // 已用完
        }
        
        return maxDailyTx - dailyTxCount[user];  // 剩余次数
    }
    
    /**
     * @notice 查询用户的流动性份额价值
     * @param user 用户地址
     * @return tokenAmount 可取回的代币数量
     * @return ethAmount 可取回的ETH数量
     */
    function getUserLiquidityValue(address user) public view returns (uint256 tokenAmount, uint256 ethAmount) {
        if (totalLiquidityShares == 0) {
            return (0, 0);
        }
        
        uint256 userShares = liquidityShares[user];
        tokenAmount = (userShares * liquidityTokens) / totalLiquidityShares;
        ethAmount = (userShares * liquidityETH) / totalLiquidityShares;
    }
    
    // 接收ETH
    receive() external payable {}
}