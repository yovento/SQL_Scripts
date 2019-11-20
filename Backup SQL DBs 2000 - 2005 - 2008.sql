set ANSI_NULLS ON
set QUOTED_IDENTIFIER ON
GO
EXEC sp_configure 'show advanced options', 1
go
reconfigure
go
exec sp_configure 'xp_cmdshell', 1
-- Configuration option 'xp_cmdshell' changed from 0 to 1. Run the RECONFIGURE statement to install.
go
reconfigure
go
----------------------------------------------------------------------------------------------------
-- OBJECT NAME            : isp_Backup
--
-- AUTHOR                 : Tara Kizer
--
-- INPUTS                 : @path - location of the backups, default backup directory used if @path is null
--                          @dbType - which database(s) to backup
--                            All, System, User, or dash followed by database name (ex. -Toolbox)
--                          @bkpType - type of backup to perform
--                            Full, TLog, Diff
--                          @retention - number of days to retain backups, -1 to retain all files
--                          @liteSpeed - perform backup using LiteSpeed (Imceda product)
--                            N, Y
--
-- OUTPUTS                : None
--
-- RETURN CODES           : 0-10 (see @error table variable at the end for the messages)
--
-- DEPENDENCIES           : None
--
-- DESCRIPTION            : Performs backups.
-- DBType                 	: All, System, User, or dash followed by database name (ex. -Toolbox)
--
-- EXAMPLES (optional)    : EXEC isp_Backup @path = '\\jrestrepo\Compartida\DBs_Unificacion_ByR', @dbType = '-dbFondosClientesAlianza', @bkpType = 'Full', @retention = 5, @liteSpeed = 'N'
----------------------------------------------------------------------------------------------------
/****** Object:  StoredProcedure [dbo].[isp_Backup]    Script Date: 11/26/2008 11:06:03 ******/
IF  EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[dbo].[isp_Backup]') AND type in (N'P', N'PC'))
DROP PROCEDURE [dbo].[isp_Backup]
GO
CREATE PROC [dbo].[isp_Backup]
(@path varchar(100), @dbType sysname = 'All', @bkpType char(4) = '-dbAlianza', @retention smallint = 2, @liteSpeed char(1) = 'N')
AS

SET NOCOUNT ON

DECLARE @now char(14)           -- current date in the form of yyyymmddhhmmss
DECLARE @dbName sysname         -- database name that is currently being processed
DECLARE @cmd nvarchar(4000)     -- dynamically created DOS command
DECLARE @result int             -- result of the dir DOS command
DECLARE @rowCnt int             -- @@ROWCOUNT
DECLARE @fileName varchar(200)  -- path and file name of the BAK file
DECLARE @edition int            -- edition of SQL Server (1 - Personal or Desktop Engine; 2 - Standard; 3 - Developer or Enterprise)
DECLARE @rc int                 -- return code
DECLARE @extension char(4)      -- extension for backup file
DECLARE @version char(2)        -- one digit version number, i.e. 8 (2000) or 9 (2005)

-- log shipping tables have been renamed in 2005
SET @version = CONVERT(char(2), SERVERPROPERTY('ProductVersion'))

IF @version NOT IN ('8', '9', '10')
BEGIN
    SET @rc = 1
    
    GOTO EXIT_ROUTINE
END

-- Enterprise and Developer editions have msdb.dbo.log_shipping* tables, other editions do not
SET @edition = CONVERT(int, SERVERPROPERTY('EngineEdition'))

-- validate input parameters
IF @dbType IS NOT NULL AND @dbType NOT IN ('All', 'System', 'User') AND @dbType NOT LIKE '-%'
BEGIN
    SET @rc = 2
    GOTO EXIT_ROUTINE
END

IF @dbType LIKE '-%' AND @version = '8'
BEGIN
    IF NOT EXISTS (SELECT * FROM master.dbo.sysdatabases WHERE [name] = SUBSTRING(@dbType, 2, DATALENGTH(@dbType)))
    BEGIN
        SET @rc = 3
        GOTO EXIT_ROUTINE
    END
END
ELSE IF @dbType LIKE '-%' AND @version in ('9','10')
BEGIN
    IF NOT EXISTS (SELECT * FROM master.sys.databases WHERE [name] = SUBSTRING(@dbType, 2, DATALENGTH(@dbType)))
    BEGIN
        SET @rc = 3
        GOTO EXIT_ROUTINE
    END
END

IF @bkpType IS NOT NULL AND @bkpType NOT IN ('Full', 'TLog', 'Diff')
BEGIN
    SET @rc = 4
    GOTO EXIT_ROUTINE
END

IF @dbType = 'System' AND @bkpType <> 'Full'
BEGIN
    SET @rc = 5
    GOTO EXIT_ROUTINE
END

IF @liteSpeed IS NOT NULL AND @liteSpeed NOT IN ('N', 'Y')
BEGIN
    SET @rc = 6
    GOTO EXIT_ROUTINE
END

-- use the default backup directory if @path is null
IF @path IS NULL
    EXEC master.dbo.xp_instance_regread N'HKEY_LOCAL_MACHINE',N'Software\Microsoft\MSSQLServer\MSSQLServer',N'BackupDirectory', @path output, 'no_output'

-- we need the backslash after the path, so add it if it wasn't provided in the input parameter
IF RIGHT(@path, 1) <> '\'
    SET @path = @path + '\'

CREATE TABLE #WhichDatabase(dbName SYSNAME NOT NULL)

-- put the databases to be backed up into temp table
IF @dbType LIKE '-%'
BEGIN
    IF @bkpType = 'TLog' AND DATABASEPROPERTYEX(SUBSTRING(@dbType, 2, DATALENGTH(@dbType)), 'RECOVERY') = 'SIMPLE'
    BEGIN
        SET @rc = 7
        GOTO EXIT_ROUTINE
    END
    
    IF @edition = 3
    BEGIN
        IF @version = '8'
        BEGIN
            IF EXISTS (SELECT * FROM msdb.dbo.log_shipping_databases WHERE database_name = SUBSTRING(@dbType, 2, DATALENGTH(@dbType)))
            BEGIN
                SET @rc = 8
                GOTO EXIT_ROUTINE
            END
        END
        ELSE IF @version in ('9','10') 
        BEGIN
            IF EXISTS (SELECT * FROM msdb.dbo.log_shipping_primary_databases WHERE primary_database = SUBSTRING(@dbType, 2, DATALENGTH(@dbType)))
            BEGIN
                SET @rc = 8
                GOTO EXIT_ROUTINE
            END
        END
    END

    INSERT INTO #WhichDatabase(dbName)
    VALUES(SUBSTRING(@dbType, 2, DATALENGTH(@dbType))) 
END
ELSE IF @dbType = 'All' 
BEGIN
    IF @edition = 3 AND @version = '8'
        INSERT INTO #WhichDatabase (dbName)
        SELECT [name]
        FROM master.dbo.sysdatabases
        WHERE 
            [name] NOT IN ('tempdb', 'ReportServerTempDB') AND
            [name] NOT IN (SELECT database_name FROM msdb.dbo.log_shipping_databases) AND
            DATABASEPROPERTYEX([name], 'IsInStandBy') = 0 AND
            DATABASEPROPERTYEX([name], 'Status') = 'ONLINE'
        ORDER BY [name]
    ELSE IF @edition = 3 AND @version in ('9','10')
        INSERT INTO #WhichDatabase (dbName)
        SELECT [name]
        FROM master.sys.databases
        WHERE 
            [name] NOT IN ('tempdb', 'ReportServerTempDB') AND
            [name] NOT IN (SELECT primary_database FROM msdb.dbo.log_shipping_primary_databases) AND
            DATABASEPROPERTYEX([name], 'IsInStandBy') = 0 AND
            DATABASEPROPERTYEX([name], 'Status') = 'ONLINE'
        ORDER BY [name]
    ELSE IF @version = '8'
        INSERT INTO #WhichDatabase (dbName)
        SELECT [name]
        FROM master.dbo.sysdatabases
        WHERE 
            [name] NOT IN ('tempdb', 'ReportServerTempDB') AND
            DATABASEPROPERTYEX([name], 'IsInStandBy') = 0 AND
            DATABASEPROPERTYEX([name], 'Status') = 'ONLINE'
        ORDER BY [name]
    ELSE -- version is 9
        INSERT INTO #WhichDatabase (dbName)
        SELECT [name]
        FROM master.sys.databases
        WHERE 
            [name] NOT IN ('tempdb', 'ReportServerTempDB') AND
            DATABASEPROPERTYEX([name], 'IsInStandBy') = 0 AND
            DATABASEPROPERTYEX([name], 'Status') = 'ONLINE'
        ORDER BY [name]
END
ELSE IF @dbType = 'System'
BEGIN
    IF @version = 8
        INSERT INTO #WhichDatabase (dbName)
        SELECT [name]
        FROM master.dbo.sysdatabases
        WHERE [name] IN ('master', 'model', 'msdb')
        ORDER BY [name]
    ELSE
        INSERT INTO #WhichDatabase (dbName)
        SELECT [name]
        FROM master.sys.databases
        WHERE [name] IN ('master', 'model', 'msdb')
        ORDER BY [name]
END
ELSE IF @dbType = 'User'
BEGIN
    IF @edition = 3 AND @version = '8'
        INSERT INTO #WhichDatabase (dbName)
        SELECT [name]
        FROM master.dbo.sysdatabases
        WHERE 
            [name] NOT IN ('master', 'model', 'msdb', 'tempdb', 'ReportServerTempDB') AND
            [name] NOT IN (SELECT database_name FROM msdb.dbo.log_shipping_databases) AND
            DATABASEPROPERTYEX([name], 'IsInStandBy') = 0 AND
            DATABASEPROPERTYEX([name], 'Status') = 'ONLINE'
        ORDER BY [name]
    ELSE IF @edition = 3 AND @version in ('9','10')
        INSERT INTO #WhichDatabase (dbName)
        SELECT [name]
        FROM master.sys.databases
        WHERE 
            [name] NOT IN ('master', 'model', 'msdb', 'tempdb', 'ReportServerTempDB') AND
            [name] NOT IN (SELECT primary_database FROM msdb.dbo.log_shipping_primary_databases) AND
            DATABASEPROPERTYEX([name], 'IsInStandBy') = 0 AND
            DATABASEPROPERTYEX([name], 'Status') = 'ONLINE'
        ORDER BY [name]
    ELSE IF @version = '8'
        INSERT INTO #WhichDatabase (dbName)
        SELECT [name]
        FROM master.dbo.sysdatabases
        WHERE 
            [name] NOT IN ('master', 'model', 'msdb', 'tempdb', 'ReportServerTempDB') AND
            DATABASEPROPERTYEX([name], 'IsInStandBy') = 0 AND
            DATABASEPROPERTYEX([name], 'Status') = 'ONLINE'
        ORDER BY [name]
    ELSE
        INSERT INTO #WhichDatabase (dbName)
        SELECT [name]
        FROM master.sys.databases
        WHERE 
            [name] NOT IN ('master', 'model', 'msdb', 'tempdb', 'ReportServerTempDB') AND
            DATABASEPROPERTYEX([name], 'IsInStandBy') = 0 AND
            DATABASEPROPERTYEX([name], 'Status') = 'ONLINE'
        ORDER BY [name]
END
ELSE -- no databases to be backed up
BEGIN
    SET @rc = 9
    GOTO EXIT_ROUTINE
END

-- Get the database to be backed up
SELECT TOP 1 @dbName = dbName
FROM #WhichDatabase

SET @rowCnt = @@ROWCOUNT

-- Iterate throught the temp table until no more databases need to be backed up
WHILE @rowCnt <> 0
BEGIN 

    IF @bkpType = 'TLog' AND @dbType IN ('All', 'User') AND DATABASEPROPERTYEX(@dbName, 'RECOVERY') = 'SIMPLE'
        PRINT 'Skipping transaction log backup of ' + @dbName
    ELSE IF @bkpType = 'Diff' AND @dbName IN ('master', 'model', 'msdb')
        PRINT 'Skipping differential backup of ' + @dbName
    ELSE
    BEGIN
        -- Build the dir command that will check to see if the directory exists
        SET @cmd = 'dir ' + @path + @dbName
    
        -- Run the dir command, put output of xp_cmdshell into @result
        EXEC @result = master..xp_cmdshell @cmd, NO_OUTPUT
    
        -- If the directory does not exist, we must create it
        IF @result <> 0
        BEGIN
            -- Build the mkdir command        
            SET @cmd = 'mkdir ' + @path + @dbName
    
            -- Create the directory
            EXEC master..xp_cmdshell @cmd, NO_OUTPUT
    
            IF @@ERROR <> 0
            BEGIN
                SET @rc = 10
                GOTO EXIT_ROUTINE
            END
        END
        -- The directory exists, so let's delete files older than two days
        ELSE IF @retention <> -1
        BEGIN
            -- Stores the name of the file to be deleted
            DECLARE @whichFile VARCHAR(1000)
    
            CREATE TABLE #DeleteOldFiles(DirInfo VARCHAR(7000))
    
            -- Build the command that will list out all of the files in a directory
            SELECT @cmd = 'dir ' + @path + @dbName + ' /OD'
    
            -- Run the dir command and put the results into a temp table
            INSERT INTO #DeleteOldFiles
            EXEC master..xp_cmdshell @cmd
    
            -- Delete all rows from the temp table except the ones that correspond to the files to be deleted
            DELETE FROM #DeleteOldFiles
            WHERE ISDATE(SUBSTRING(DirInfo, 1, 10)) = 0 OR DirInfo LIKE '%<DIR>%' OR SUBSTRING(DirInfo, 1, 10) >= GETDATE() - @retention
    
            -- Get the file name portion of the row that corresponds to the file to be deleted
            SELECT TOP 1 @whichFile = SUBSTRING(DirInfo, LEN(DirInfo) -  PATINDEX('% %', REVERSE(DirInfo)) + 2, LEN(DirInfo)) 
            FROM #DeleteOldFiles        
    
            SET @rowCnt = @@ROWCOUNT
            
            -- Interate through the temp table until there are no more files to delete
            WHILE @rowCnt <> 0
            BEGIN
                -- Build the del command
                SELECT @cmd = 'del ' + @path + + @dbName + '\' + @whichFile + ' /Q /F'
                
                -- Delete the file
                EXEC master..xp_cmdshell @cmd, NO_OUTPUT
                
                -- To move to the next file, the current file name needs to be deleted from the temp table
                DELETE FROM #DeleteOldFiles
                WHERE SUBSTRING(DirInfo, LEN(DirInfo) -  PATINDEX('% %', REVERSE(DirInfo)) + 2, LEN(DirInfo))  = @whichFile
    
                -- Get the file name portion of the row that corresponds to the file to be deleted
                SELECT TOP 1 @whichFile = SUBSTRING(DirInfo, LEN(DirInfo) -  PATINDEX('% %', REVERSE(DirInfo)) + 2, LEN(DirInfo)) 
                FROM #DeleteOldFiles
            
                SET @rowCnt = @@ROWCOUNT
            END
            DROP TABLE #DeleteOldFiles
        END
        -- Get the current date using style 120, remove all dashes, spaces, and colons
        SET @now = REPLACE(REPLACE(REPLACE(CONVERT(VARCHAR(50), GETDATE(), 120), '-', ''), ' ', ''), ':', '')
    
        SET @extension =
            CASE
                WHEN @bkpType = 'Full' THEN '.BAK'
                WHEN @bkpType = 'TLog' THEN '.TRN'
                ELSE '.DIF'
            END
    
        -- Build the backup path and file name, backup the database
        IF @liteSpeed = 'N'
        BEGIN
            SET @fileName = @path + @dbName + '\' + @dbName + '_' + @now + @extension
            IF @bkpType = 'FULL'
                BACKUP DATABASE @dbName
                TO DISK = @filename
                WITH INIT
            ELSE IF @bkpType = 'DIFF'
                BACKUP DATABASE @dbName
                TO DISK = @filename
                WITH INIT, DIFFERENTIAL
            ELSE
                BACKUP LOG @dbName
                TO DISK = @filename
                WITH INIT    
        END
        ELSE
        BEGIN
            SET @fileName = @path + @dbName + '\' + @dbName + '_LS_' + @now + @extension
    
            DECLARE @numProcs INT -- stores the number of processors that the server has registered
    
            -- Get the number of processors that the server has
            EXEC master..xp_regread 
              @rootkey = 'HKEY_LOCAL_MACHINE', 
              @key = 'SYSTEM\CurrentControlSet\Control\Session Manager',
              @value_name = 'RegisteredProcessors',
              @value = @numProcs OUTPUT
            
            --  We want n - 1 threads, where n is the number of processors
            SET @numProcs = @numProcs - 1
    
            IF @bkpType = 'FULL'
                EXEC master.dbo.xp_backup_database
                    @database = @dbName,
                    @filename = @fileName,
                    @threads = @numProcs,
                    @init = 1
            ELSE IF @bkpType = 'DIFF'
                EXEC master.dbo.xp_backup_database
                    @database = @dbName,
                    @filename = @fileName,
                    @threads = @numProcs,
                    @init = 1,
                    @with = 'DIFFERENTIAL'
            ELSE
                EXEC master.dbo.xp_backup_log
                    @database = @dbName,
                    @filename = @fileName,
                    @threads = @numProcs,
                    @init = 1
        END
    END
        -- To move onto the next database, the current database name needs to be deleted from the temp table
        DELETE FROM #WhichDatabase
        WHERE dbName = @dbName
    
        -- Get the database to be backed up
        SELECT TOP 1 @dbName = dbName
        FROM #WhichDatabase
    
        SET @rowCnt = @@ROWCOUNT
        
        -- Let the system rest for 5 seconds before starting on the next backup
        WAITFOR DELAY '00:00:05'
END

SET @rc = 0

EXIT_ROUTINE:

IF @rc <> 0
BEGIN
    DECLARE @rm varchar(500)
    DECLARE @error table (returnCode int PRIMARY KEY CLUSTERED, returnMessage varchar(500))

    INSERT INTO @error(returnCode, returnMessage)
    SELECT  0, 'Success' UNION ALL
    SELECT  1, 'Version is not 2000 or 2005' UNION ALL
    SELECT  2, 'Invalid option passed to @dbType' UNION ALL
    SELECT  3, 'Database passed to @dbType does not exist' UNION ALL
    SELECT  4, 'Invalid option passed to @bkpType' UNION ALL
    SELECT  5, 'Only full backups are allowed on system databases'
    SELECT  6, 'Invalid option passed to @liteSpeed' UNION ALL
    SELECT  7, 'Can not backup tlog when using SIMPLE recovery model' UNION ALL
    SELECT  8, 'Will not backup the tlog on a log shipped database' UNION ALL
    SELECT  9, 'No databases to be backed up' UNION ALL
    SELECT 10, 'Unable to create directory'

    SELECT @rm = returnMessage 
    FROM @error 
    WHERE returnCode = @rc

    RAISERROR(@rm, 16, 1)
END

RETURN @rc
