CREATE TABLE IF NOT EXISTS `memecoins` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `ticker` VARCHAR(10) NOT NULL,
  `name` VARCHAR(50) NOT NULL,
  `image` VARCHAR(255) DEFAULT NULL,
  `creator_citizenid` VARCHAR(50) NOT NULL,
  `creator_name` VARCHAR(100) DEFAULT NULL,
  -- Constant-product bonding curve (same shape as pump.fun/Uniswap v2):
  -- currency_reserve * token_reserve = k, stays constant across trades.
  -- price = currency_reserve / token_reserve. token_reserve starts at the
  -- full supply (nobody holds anything yet) and shrinks as people buy in --
  -- the pool getting thinner relative to a trade's size is exactly what
  -- makes both pumps and dumps hit harder the more of the supply is
  -- already in player hands.
  `currency_reserve` DECIMAL(20,4) NOT NULL,
  `token_reserve` DECIMAL(24,4) NOT NULL,
  `total_supply` DECIMAL(24,4) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `rugged` TINYINT(1) NOT NULL DEFAULT 0, -- creator dumped their entire holding at once
  PRIMARY KEY (`id`),
  UNIQUE KEY `ticker` (`ticker`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `memecoin_holdings` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(50) NOT NULL,
  `coin_id` INT NOT NULL,
  `amount` DECIMAL(24,4) NOT NULL DEFAULT 0,
  `avg_buy_price` DECIMAL(20,10) NOT NULL DEFAULT 0, -- for profit/loss display, not curve math
  PRIMARY KEY (`id`),
  UNIQUE KEY `citizenid_coin` (`citizenid`, `coin_id`),
  KEY `coin_id` (`coin_id`),
  CONSTRAINT `fk_memecoin_holdings_coin` FOREIGN KEY (`coin_id`) REFERENCES `memecoins` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `memecoin_trades` (
  `id` INT NOT NULL AUTO_INCREMENT,
  `coin_id` INT NOT NULL,
  `citizenid` VARCHAR(50) NOT NULL,
  `trader_name` VARCHAR(100) DEFAULT NULL, -- snapshotted at trade time, same pattern as memecoins.creator_name
  `type` ENUM('buy','sell') NOT NULL,
  `amount` DECIMAL(24,4) NOT NULL, -- tokens bought/sold
  `currency` DECIMAL(20,4) NOT NULL, -- money spent/received
  `price` DECIMAL(20,10) NOT NULL, -- price per token immediately after this trade
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `coin_id_created` (`coin_id`, `created_at`),
  CONSTRAINT `fk_memecoin_trades_coin` FOREIGN KEY (`coin_id`) REFERENCES `memecoins` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
