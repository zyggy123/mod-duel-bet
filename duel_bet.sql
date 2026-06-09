CREATE TABLE IF NOT EXISTS `duel_bets` (
  `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
  `player1_guid` INT UNSIGNED NOT NULL,
  `player2_guid` INT UNSIGNED NOT NULL,
  `amount` BIGINT UNSIGNED NOT NULL,
  `status` TINYINT UNSIGNED DEFAULT 0 COMMENT '0: Pending, 1: Active, 2: In-Duel',
  PRIMARY KEY (`id`),
  INDEX `idx_p1` (`player1_guid`),
  INDEX `idx_p2` (`player2_guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `duel_bet_stats` (
  `guid` INT UNSIGNED NOT NULL,
  `total_duels` INT UNSIGNED DEFAULT 0,
  `total_won` INT UNSIGNED DEFAULT 0,
  `total_profit` BIGINT DEFAULT 0,
  PRIMARY KEY (`guid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
