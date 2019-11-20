USE [databaseName]
Go
---*********ADD EXEC PERMS TO ALL SPS******--------------
DECLARE @cmd varchar(8000)
DECLARE @objectCount int
DECLARE @OwnerName varchar(128)
DECLARE @ObjectName varchar(128)
DECLARE @user VARCHAR(100) = 'myuser';

CREATE TABLE #StoredProcedures
(OID int IDENTITY (1,1),
StoredProcOwner varchar(128) NOT NULL,
StoredProcName varchar(128) NOT NULL)


INSERT INTO #StoredProcedures (StoredProcOwner, StoredProcName)
SELECT 
	u.[Name], 
	o.[Name]
FROM 
	dbo.sysobjects o
	INNER JOIN dbo.sysusers u
	ON o.uid = u.uid
WHERE o.Type = 'P';


SELECT @objectCount = MAX(OID) FROM #StoredProcedures

WHILE @objectCount > 0
BEGIN


	SELECT @OwnerName = StoredProcOwner,
	@ObjectName = StoredProcName
	FROM #StoredProcedures
	WHERE OID = @objectCount


	SELECT @cmd = 'GRANT EXEC ON ' + '[' + @OwnerName + ']' + '.' + '[' + @ObjectName + ']' + ' TO ' + @user

	SELECT @cmd;
	
	EXEC(@cmd);


SET @objectCount = @objectCount- 1;

END

DROP TABLE #StoredProcedures;