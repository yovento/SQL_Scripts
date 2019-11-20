SET NOCOUNT ON

DECLARE @DatabaseUserName [SYSNAME];
Declare @userName varchar(500)
Set @userName = 'alianza2010'
SET @DatabaseUserName = @userName;


DECLARE @errStatement   VARCHAR(1000),
        @msgStatement   VARCHAR(1000),
        @DatabaseUserID SMALLINT,
        @ServerUserName SYSNAME,
        @RoleName       VARCHAR(1000),
        @ObjectID       INT,
        @ObjectName     VARCHAR(1000),
        @StateDesc       VARCHAR(1000),
        @permissionName VARCHAR(1000)
        
        
      

SELECT @DatabaseUserID = su.[uid],
       @ServerUserName = sl.[loginname]
FROM   dbo.[sysusers] su
       INNER JOIN [master].dbo.[syslogins] sl
         ON su.[sid] = sl.[sid]
WHERE  su.[name] = @DatabaseUserName

IF @DatabaseUserID IS NULL
  BEGIN
      SET @errStatement = 'User ' + @DatabaseUserName + ' does not exist in ' + DB_NAME() + CHAR(13) + 'Please provide the name of a current user in ' + DB_NAME() + ' you wish to script.'

      RAISERROR(@errStatement,
                16,
                1)
  END
ELSE
  BEGIN
      SET @msgStatement = '--Security creation script for user ' + @ServerUserName + CHAR(13) + '--Created At: ' + CONVERT(VARCHAR, GETDATE(), 100) + REPLACE(CONVERT(VARCHAR, GETDATE(), 108), ':', '') + CHAR(13) + '--Created By: ' + SUSER_NAME() + CHAR(13) + '--Add User To Database' + CHAR(13) + 'USE [' + DB_NAME() + ']' + CHAR(13) + 'EXEC [sp_grantdbaccess]' + CHAR(13) + CHAR(9) + '@loginame = ''' + @ServerUserName + ''',' + CHAR(13) + CHAR(9) + '@name_in_db = ''' + @DatabaseUserName + '''' + ';'+ CHAR(13) + 'GO' + CHAR(13) + '--Add User To Roles'

      PRINT @msgStatement

      DECLARE _sysusers CURSOR LOCAL FORWARD_ONLY READ_ONLY FOR
        SELECT [name]
        FROM   [dbo].[sysusers]
        WHERE  [uid] IN (SELECT [groupuid]
                         FROM   [dbo].[sysmembers]
                         WHERE  [memberuid] = @DatabaseUserID)

      OPEN _sysusers

      FETCH NEXT FROM _sysusers INTO @RoleName

      WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @msgStatement = 'EXEC [sp_addrolemember]' + CHAR(13) + CHAR(9) + '@rolename = ''' + @RoleName + ''',' + CHAR(13) + CHAR(9) + '@membername = ''' + @DatabaseUserName + ''''  + ';' ;

            PRINT @msgStatement

            FETCH NEXT FROM _sysusers INTO @RoleName
        END
        
        
        CLOSE _sysusers;
        
        DEALLOCATE _sysusers;
        
       --Database level perms;
       
       PRINT '--Set Database level Permissions';
       DECLARE _databaselevelperms CURSOR LOCAL FORWARD_ONLY READ_ONLY FOR      
		SELECT 
			 sdp.state_desc,
			 sdp.permission_name
		FROM 
			sys.database_permissions sdp WITH(NOLOCK)
			
			JOIN sysusers  su WITH(NOLOCK)
				ON su.uid = sdp.grantee_principal_id
				
		WHERE 
			su.name = @userName
			AND sdp.class_desc = 'DATABASE';
	

      OPEN _databaselevelperms;
      
      FETCH NEXT FROM _databaselevelperms INTO @StateDesc, @PermissionName;
      
      WHILE @@FETCH_STATUS = 0 
      BEGIN 
      
		PRINT @StateDesc  + CHAR(13) + CHAR(9) + @PermissionName  + CHAR(13) + CHAR(9) +   'TO '  + @userName + ';';
		
		FETCH NEXT FROM _databaselevelperms INTO @StateDesc, @PermissionName
		
	  END
	  
	  CLOSE _databaselevelperms;

      DEALLOCATE _databaselevelperms;

      SET @msgStatement = 'GO' + CHAR(13) + '--Set Object Specific Permissions'

      PRINT @msgStatement;

      DECLARE _sysobjects CURSOR LOCAL FORWARD_ONLY READ_ONLY FOR
        SELECT DISTINCT( [sysobjects].[id] ),
                       '[' + USER_NAME([sysobjects].[uid]) + '].[' + [sysobjects].[name] + ']'
        FROM   [dbo].[sysprotects]
               INNER JOIN [dbo].[sysobjects]
                 ON [sysprotects].[id] = [sysobjects].[id]
        WHERE  [sysprotects].[uid] = @DatabaseUserID;

      OPEN _sysobjects;

      FETCH NEXT FROM _sysobjects INTO @ObjectID, @ObjectName;

      WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @msgStatement = '';

            IF EXISTS(SELECT 1
                      FROM   [dbo].[sysprotects]
                      WHERE  [id] = @ObjectID
                             AND [uid] = @DatabaseUserID
                             AND [action] = 193
                             AND [protecttype] = 205)
              SET @msgStatement = @msgStatement + 'SELECT,';

            IF EXISTS(SELECT 1
                      FROM   [dbo].[sysprotects]
                      WHERE  [id] = @ObjectID
                             AND [uid] = @DatabaseUserID
                             AND [action] = 195
                             AND [protecttype] = 205)
              SET @msgStatement = @msgStatement + 'INSERT,';

            IF EXISTS(SELECT 1
                      FROM   [dbo].[sysprotects]
                      WHERE  [id] = @ObjectID
                             AND [uid] = @DatabaseUserID
                             AND [action] = 197
                             AND [protecttype] = 205)
              SET @msgStatement = @msgStatement + 'UPDATE,';

            IF EXISTS(SELECT 1
                      FROM   [dbo].[sysprotects]
                      WHERE  [id] = @ObjectID
                             AND [uid] = @DatabaseUserID
                             AND [action] = 196
                             AND [protecttype] = 205)
              SET @msgStatement = @msgStatement + 'DELETE,';

            IF EXISTS(SELECT 1
                      FROM   [dbo].[sysprotects]
                      WHERE  [id] = @ObjectID
                             AND [uid] = @DatabaseUserID
                             AND [action] = 224
                             AND [protecttype] = 205)
              SET @msgStatement = @msgStatement + 'EXECUTE,';

            IF EXISTS(SELECT 1
                      FROM   [dbo].[sysprotects]
                      WHERE  [id] = @ObjectID
                             AND [uid] = @DatabaseUserID
                             AND [action] = 26
                             AND [protecttype] = 205)
              SET @msgStatement = @msgStatement + 'REFERENCES,';

            IF LEN(@msgStatement) > 0
              BEGIN
                  IF RIGHT(@msgStatement, 1) = ','
                    SET @msgStatement = LEFT(@msgStatement, LEN(@msgStatement) - 1);

                  SET @msgStatement = 'GRANT' + CHAR(13) + CHAR(9) + @msgStatement + CHAR(13) + CHAR(9) + 'ON ' + @ObjectName + CHAR(13) + CHAR(9) + 'TO ' + @DatabaseUserName + ';' ;

                  PRINT @msgStatement;
              END

            SET @msgStatement = '';

            IF EXISTS(SELECT 1
                      FROM   [dbo].[sysprotects]
                      WHERE  [id] = @ObjectID
                             AND [uid] = @DatabaseUserID
                             AND [action] = 193
                             AND [protecttype] = 206)
              SET @msgStatement = @msgStatement + 'SELECT,'

            IF EXISTS(SELECT 1
                      FROM   [dbo].[sysprotects]
                      WHERE  [id] = @ObjectID
                             AND [uid] = @DatabaseUserID
                             AND [action] = 195
                             AND [protecttype] = 206)
              SET @msgStatement = @msgStatement + 'INSERT,';

            IF EXISTS(SELECT 1
                      FROM   [dbo].[sysprotects]
                      WHERE  [id] = @ObjectID
                             AND [uid] = @DatabaseUserID
                             AND [action] = 197
                             AND [protecttype] = 206)
              SET @msgStatement = @msgStatement + 'UPDATE,';

            IF EXISTS(SELECT 1
                      FROM   [dbo].[sysprotects]
                      WHERE  [id] = @ObjectID
                             AND [uid] = @DatabaseUserID
                             AND [action] = 196
                             AND [protecttype] = 206)
              SET @msgStatement = @msgStatement + 'DELETE,'

            IF EXISTS(SELECT 1
                      FROM   [dbo].[sysprotects]
                      WHERE  [id] = @ObjectID
                             AND [uid] = @DatabaseUserID
                             AND [action] = 224
                             AND [protecttype] = 206)
              SET @msgStatement = @msgStatement + 'EXECUTE,';

            IF EXISTS(SELECT *
                      FROM   [dbo].[sysprotects]
                      WHERE  [id] = @ObjectID
                             AND [uid] = @DatabaseUserID
                             AND [action] = 26
                             AND [protecttype] = 206)
              SET @msgStatement = @msgStatement + 'REFERENCES,';

            IF LEN(@msgStatement) > 0
              BEGIN
                  IF RIGHT(@msgStatement, 1) = ','
                    SET @msgStatement = LEFT(@msgStatement, LEN(@msgStatement) - 1)

                  SET @msgStatement = 'DENY' + CHAR(13) + CHAR(9) + @msgStatement + CHAR(13) + CHAR(9) + 'ON ' + @ObjectName + CHAR(13) + CHAR(9) + 'TO ' + @DatabaseUserName + ';' ;

                  PRINT @msgStatement;
              END

            FETCH NEXT FROM _sysobjects INTO @ObjectID, @ObjectName;
        END

      CLOSE _sysobjects;

      DEALLOCATE _sysobjects;
      
   

      PRINT 'GO'
  END 


SET NOCOUNT OFF