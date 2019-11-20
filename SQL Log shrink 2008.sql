Reemplazar set @DbName = 'dbAlianzaProyectar' por la base de datos correcta

DECLARE @DbName VarChar(50)
DECLARE @DbRecoveryModal varchar(50)
DECLARE @LogName varchar(50)
DECLARE @DBIsSimple_Shrink varchar(4000)
DECLARE @SetRecoverySimple varchar(4000)
DECLARE @ShrinkDBLog varchar(4000)
DECLARE @ReSetRecovery varchar(4000)
DECLARE @GetLogName varchar(4000)
set @DbName = 'dbAlianzaProyectar'
-- get the recovery model of the database and assign it to @DbRecoveryModal
Set @DbRecoveryModal = CAST(DATABASEPROPERTYEX(@DbName, 'Recovery') AS varchar(40))
-- get the logical log file name of the database and assign it to @GetLogName
set @GetLogName =('USE ' + @DbName + ' select name from sys.database_files where type = 1')
-- a temporary table is created to hold the logical file name of the database and then assign the value to @LogName
-- The table is then dropped. Drop the table if it exists
IF EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[DBResultSet]') AND type in (N'U'))
DROP TABLE [dbo].[DBResultSet]
-- create table and set the @LogName varable
CREATE TABLE DBResultSet (SetLogName VarChar(400))
INSERT INTO DBResultSet EXEC(@GetLogName) 
SET @LogName = (select SetLogName from DBResultSet)
Drop Table DBResultSet
-- truncate the transaction based on the database recovery model
IF @DbRecoveryModal = 'Simple'
BEGIN
-- Shrink the truncated log file to 2MB.
set @DBIsSimple_Shrink ='USE ' + @DbName + ' DBCC SHRINKFILE (' + @LogName + ', 2)'
EXEC(@DBIsSimple_Shrink)
END
ELSE IF @DbRecoveryModal = 'BULK_LOGGED'
BEGIN
-- Truncate the log by changing the database recovery model to SIMPLE.
set @SetRecoverySimple = 'ALTER DATABASE ' + @DbName + ' SET RECOVERY SIMPLE'
EXEC (@SetRecoverySimple)
-- Shrink the truncated log file to 2 MB.
set @ShrinkDBLog ='USE ' + @DbName + ' DBCC SHRINKFILE (' + @LogName + ', 2)';
EXEC(@ShrinkDBLog)
-- Reset the database recovery model.
set @ReSetRecovery = 'ALTER DATABASE ' + @DbName + ' SET RECOVERY BULK_LOGGED';
EXEC (@ReSetRecovery)
END
ElSE
BEGIN
-- Truncate the log by changing the database recovery model to SIMPLE.
set @SetRecoverySimple = 'ALTER DATABASE ' + @DbName + ' SET RECOVERY SIMPLE'
EXEC (@SetRecoverySimple)
-- Shrink the truncated log file to 2 MB.
set @ShrinkDBLog ='USE ' + @DbName + ' DBCC SHRINKFILE (' + @LogName + ', 2)'
EXEC(@ShrinkDBLog) 
-- Reset the database recovery
set @ReSetRecovery = 'ALTER DATABASE ' + @DbName + ' SET RECOVERY FULL'
EXEC (@ReSetRecovery)
END
