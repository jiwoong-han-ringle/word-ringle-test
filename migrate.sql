-- Create database if not exists
CREATE DATABASE IF NOT EXISTS word_ringle_development;
USE word_ringle_development;

-- Create words table
CREATE TABLE IF NOT EXISTS words (
  word_id INT PRIMARY KEY AUTO_INCREMENT,
  word VARCHAR(50) NOT NULL,
  lemma VARCHAR(50) NOT NULL UNIQUE,
  word_type VARCHAR(20) NOT NULL,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create words_used table
CREATE TABLE IF NOT EXISTS words_used (
  id INT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  history JSON,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX idx_user_id (user_id)
);

-- Create user_counts table
CREATE TABLE IF NOT EXISTS user_counts (
  id INT PRIMARY KEY AUTO_INCREMENT,
  user_id BIGINT NOT NULL,
  date DATE NOT NULL,
  total_words INT DEFAULT 0,
  unique_words INT DEFAULT 0,
  created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY unique_user_date (user_id, date)
);

-- Create schema_migrations table for Rails
CREATE TABLE IF NOT EXISTS schema_migrations (
  version VARCHAR(255) NOT NULL PRIMARY KEY
);

-- Insert migration versions
INSERT IGNORE INTO schema_migrations (version) VALUES
('20250904064832'),
('20250904064938'), 
('20250904065015');

SHOW TABLES;