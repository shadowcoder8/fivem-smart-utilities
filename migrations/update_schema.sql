-- Update player_internet table to include upgrade_tier
ALTER TABLE `player_internet`
ADD COLUMN `upgrade_tier` VARCHAR(255) DEFAULT 'Basic' COMMENT 'Internet plan tier (e.g., Basic, Premium, Ultra)';

-- Create trash_log table
CREATE TABLE IF NOT EXISTS `trash_log` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(50) NOT NULL COMMENT 'Player Citizen ID',
  `time` TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Time of the log entry',
  `action_type` VARCHAR(50) NOT NULL COMMENT 'Type of action (e.g., collected, dumped_legal, dumped_illegal)',
  `amount_collected` INT DEFAULT 0 COMMENT 'Amount of trash collected (e.g., in kg)',
  `fine_amount` DECIMAL(10, 2) DEFAULT 0.00 COMMENT 'Amount of fine issued for illegal dumping',
  INDEX `idx_citizenid` (`citizenid`),
  INDEX `idx_action_type` (`action_type`)
) COMMENT='Logs trash collection activities and fines';

-- Example update for existing entries in player_internet to have a default tier if needed
-- This assumes you want all existing users to start on 'Basic' if their tier is NULL.
-- UPDATE `player_internet` SET `upgrade_tier` = 'Basic' WHERE `upgrade_tier` IS NULL;

-- Note: The fxmanifest.lua will need to be updated to run this SQL file if your framework supports it,
-- or it needs to be run manually. For QBCore, this is often handled by `qb-core/server/player.lua` or similar
-- by checking a version number or by adding it to a list of SQL files to import.
-- For this exercise, I will assume manual execution or framework-specific handling.

-- Add a column to store router position for each property in player_internet table
ALTER TABLE `player_internet`
ADD COLUMN `router_pos_x` DECIMAL(10, 2) DEFAULT NULL COMMENT 'X coordinate of the installed router',
ADD COLUMN `router_pos_y` DECIMAL(10, 2) DEFAULT NULL COMMENT 'Y coordinate of the installed router',
ADD COLUMN `router_pos_z` DECIMAL(10, 2) DEFAULT NULL COMMENT 'Z coordinate of the installed router';

-- Add a column to player_internet to track if the router has been installed
ALTER TABLE `player_internet`
ADD COLUMN `is_router_installed` BOOLEAN DEFAULT FALSE COMMENT 'Tracks if the internet router has been installed';
