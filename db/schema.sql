-- Database schema for the Java Login App.
-- Run as the RDS/MySQL admin user:  mysql -h <endpoint> -u admin -p < schema.sql
-- Names (UserDB, Employee, column names) must match what the Java code uses.

CREATE DATABASE IF NOT EXISTS UserDB;
USE UserDB;

CREATE TABLE IF NOT EXISTS Employee (
  id         INT UNSIGNED AUTO_INCREMENT NOT NULL,
  first_name VARCHAR(250),
  last_name  VARCHAR(250),
  email      VARCHAR(250),
  username   VARCHAR(250),
  password   VARCHAR(250),
  regdate    TIMESTAMP,
  PRIMARY KEY (id)
);

-- Dedicated least-privilege user for the app (do not run the app as admin/root).
-- Change the password, and restrict '%' to your app subnet if you can (e.g. '10.0.%').
CREATE USER IF NOT EXISTS 'appuser'@'%' IDENTIFIED BY 'CHANGE_ME_STRONG_PASSWORD';
GRANT SELECT, INSERT ON UserDB.Employee TO 'appuser'@'%';
FLUSH PRIVILEGES;

-- Quick checks
-- SHOW TABLES;
-- DESCRIBE Employee;
-- SELECT * FROM Employee;
