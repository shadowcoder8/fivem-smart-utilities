-- Smart Utilities Database Schema Creation
-- Run this file to create all required tables for the Smart Utilities system

-- Create player_internet table if it doesn't exist
CREATE TABLE IF NOT EXISTS `player_internet` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(50) NOT NULL COMMENT 'Player Citizen ID',
  `property_id` VARCHAR(50) NOT NULL COMMENT 'Property identifier',
  `upgrade_tier` VARCHAR(255) DEFAULT 'Basic' COMMENT 'Internet plan tier (e.g., Basic, Premium, Ultra)',
  `is_router_installed` BOOLEAN DEFAULT FALSE COMMENT 'Tracks if the internet router has been installed',
  `router_pos_x` DECIMAL(10, 2) DEFAULT NULL COMMENT 'X coordinate of the installed router',
  `router_pos_y` DECIMAL(10, 2) DEFAULT NULL COMMENT 'Y coordinate of the installed router',
  `router_pos_z` DECIMAL(10, 2) DEFAULT NULL COMMENT 'Z coordinate of the installed router',
  `created_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `unique_property_subscription` (`citizenid`, `property_id`)
) COMMENT='Stores player internet subscriptions and router installations';

-- Create trash_log table if it doesn't exist
CREATE TABLE IF NOT EXISTS `trash_log` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `citizenid` VARCHAR(50) NOT NULL COMMENT 'Player Citizen ID',
  `time` TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'Time of the log entry',
  `action_type` VARCHAR(50) NOT NULL COMMENT 'Type of action (e.g., collected, dumped_legal, dumped_illegal)',
  `amount_collected` INT DEFAULT 0 COMMENT 'Amount of trash collected (e.g., in kg)',
  `fine_amount` DECIMAL(10, 2) DEFAULT 0.00 COMMENT 'Amount of fine issued for illegal dumping',
  `location_x` DECIMAL(10, 2) DEFAULT NULL COMMENT 'X coordinate of action',
  `location_y` DECIMAL(10, 2) DEFAULT NULL COMMENT 'Y coordinate of action',
  `location_z` DECIMAL(10, 2) DEFAULT NULL COMMENT 'Z coordinate of action'
) COMMENT='Logs trash collection activities and fines';

-- Create power_outages table for tracking power system state
CREATE TABLE IF NOT EXISTS `power_outages` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `zone_id` VARCHAR(50) NOT NULL COMMENT 'Power zone identifier',
  `is_active` BOOLEAN DEFAULT FALSE COMMENT 'Whether outage is currently active',
  `started_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'When outage started',
  `ended_at` TIMESTAMP NULL COMMENT 'When outage ended',
  `cause` VARCHAR(100) DEFAULT 'Unknown' COMMENT 'Cause of outage (sabotage, maintenance, etc.)',
  `triggered_by` VARCHAR(50) DEFAULT NULL COMMENT 'Player who triggered the outage'
) COMMENT='Tracks power outage history and current state';

-- Create water_leaks table for tracking water system state
CREATE TABLE IF NOT EXISTS `water_leaks` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `leak_id` VARCHAR(50) NOT NULL UNIQUE COMMENT 'Unique leak identifier',
  `source_id` VARCHAR(50) NOT NULL COMMENT 'Water source identifier',
  `location_x` DECIMAL(10, 2) NOT NULL COMMENT 'X coordinate of leak',
  `location_y` DECIMAL(10, 2) NOT NULL COMMENT 'Y coordinate of leak',
  `location_z` DECIMAL(10, 2) NOT NULL COMMENT 'Z coordinate of leak',
  `is_active` BOOLEAN DEFAULT TRUE COMMENT 'Whether leak is currently active',
  `severity` INT DEFAULT 1 COMMENT 'Leak severity (1-5)',
  `started_at` TIMESTAMP DEFAULT CURRENT_TIMESTAMP COMMENT 'When leak started',
  `repaired_at` TIMESTAMP NULL COMMENT 'When leak was repaired',
  `triggered_by` VARCHAR(50) DEFAULT NULL COMMENT 'Player who triggered the leak'
) COMMENT='Tracks water leak history and current state';

-- Create internet_hubs table for tracking internet infrastructure
CREATE TABLE IF NOT EXISTS `internet_hubs` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `hub_id` VARCHAR(50) NOT NULL UNIQUE COMMENT 'Hub identifier',
  `hub_name` VARCHAR(100) NOT NULL COMMENT 'Hub display name',
  `location_x` DECIMAL(10, 2) NOT NULL COMMENT 'X coordinate of hub',
  `location_y` DECIMAL(10, 2) NOT NULL COMMENT 'Y coordinate of hub',
  `location_z` DECIMAL(10, 2) NOT NULL COMMENT 'Z coordinate of hub',
  `is_operational` BOOLEAN DEFAULT TRUE COMMENT 'Whether hub is operational',
  `last_outage` TIMESTAMP NULL COMMENT 'Last time hub went down',
  `maintenance_mode` BOOLEAN DEFAULT FALSE COMMENT 'Whether hub is in maintenance'
) COMMENT='Tracks internet hub infrastructure and status';

-- Add performance indexes
CREATE INDEX IF NOT EXISTS `idx_player_internet_lookup` ON `player_internet` (`citizenid`, `property_id`);
CREATE INDEX IF NOT EXISTS `idx_player_internet_property` ON `player_internet` (`property_id`);
CREATE INDEX IF NOT EXISTS `idx_trash_log_citizenid` ON `trash_log` (`citizenid`);
CREATE INDEX IF NOT EXISTS `idx_trash_log_time` ON `trash_log` (`time`);
CREATE INDEX IF NOT EXISTS `idx_trash_log_action` ON `trash_log` (`action_type`);
CREATE INDEX IF NOT EXISTS `idx_power_outages_zone` ON `power_outages` (`zone_id`);
CREATE INDEX IF NOT EXISTS `idx_power_outages_active` ON `power_outages` (`is_active`);
CREATE INDEX IF NOT EXISTS `idx_water_leaks_source` ON `water_leaks` (`source_id`);
CREATE INDEX IF NOT EXISTS `idx_water_leaks_active` ON `water_leaks` (`is_active`);
CREATE INDEX IF NOT EXISTS `idx_internet_hubs_operational` ON `internet_hubs` (`is_operational`);

-- Insert default internet hubs if they don't exist
INSERT IGNORE INTO `internet_hubs` (`hub_id`, `hub_name`, `location_x`, `location_y`, `location_z`) VALUES
('downtown_hub', 'Downtown Internet Hub', 215.0, -810.0, 30.0),
('vinewood_hub', 'Vinewood Internet Hub', 120.0, 560.0, 183.0),
('sandy_hub', 'Sandy Shores Internet Hub', 1960.0, 3740.0, 32.0),
('paleto_hub', 'Paleto Bay Internet Hub', -140.0, 6360.0, 31.0);

-- Create utility functions table for storing system state
CREATE TABLE IF NOT EXISTS `utility_system_state` (
  `id` INT AUTO_INCREMENT PRIMARY KEY,
  `system_name` VARCHAR(50) NOT NULL UNIQUE COMMENT 'System identifier (power, water, internet, trash)',
  `state_data` JSON COMMENT 'JSON data storing system state',
  `last_updated` TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) COMMENT='Stores persistent system state data';

-- Insert default system states
INSERT IGNORE INTO `utility_system_state` (`system_name`, `state_data`) VALUES
('power', '{"zones": {}, "maintenance_mode": false}'),
('water', '{"sources": {}, "active_leaks": {}}'),
('internet', '{"hubs": {}, "global_outage": false}'),
('trash', '{"bins": {}, "dumpsters": {}, "illegal_dumps": {}}');

-- Performance optimization: Add composite indexes for common queries
CREATE INDEX IF NOT EXISTS `idx_trash_log_citizen_time` ON `trash_log` (`citizenid`, `time`);
CREATE INDEX IF NOT EXISTS `idx_power_outages_zone_active` ON `power_outages` (`zone_id`, `is_active`);
CREATE INDEX IF NOT EXISTS `idx_water_leaks_source_active` ON `water_leaks` (`source_id`, `is_active`);

COMMIT;