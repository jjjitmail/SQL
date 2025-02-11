SELECT *  
FROM sys.server_principals AS pr   
JOIN sys.server_permissions AS pe   
    ON pe.grantee_principal_id = pr.principal_id
	WHERE pr.name = 'CORP\admin-tam'
	
--use [FGHDatabase20180319]

DECLARE @USE_DEFAULT_DATABASE_QUERY AS VARCHAR(200);
DECLARE @USE_DATABASE_QUERY AS VARCHAR(200);
SET @USE_DEFAULT_DATABASE_QUERY = N'USE ' + QUOTENAME('FGHDatabase');

EXEC (@USE_DEFAULT_DATABASE_QUERY)

DECLARE @RNHBusers TABLE( name varchar(50) NOT NULL )
DECLARE @FGHusers TABLE( name varchar(50) NOT NULL )
DECLARE @UserMappingTable TABLE(LoginName nvarchar(200), DBname nvarchar(200), Username nvarchar(200), AliasName nvarchar(200))

INSERT INTO @RNHBusers (name) select name from sys.sysusers where name LIKE  'RNHB\SQL_%' 
INSERT INTO @FGHusers (name) select name from sys.sysusers where name LIKE 'FGH\%' 
INSERT INTO @UserMappingTable EXEC master..sp_msloginmappings 

DECLARE @RNHBUserName as VARCHAR(50);
DECLARE @CORPUserName as VARCHAR(50);  
DECLARE @FGHUserName as VARCHAR(50);
DECLARE @RolName as VARCHAR(50);
DECLARE @DBName as VARCHAR(50);
DECLARE @DBLANGUAGE as VARCHAR(50);
DECLARE @SqlStatement as VARCHAR(5000);
DECLARE @CORP as VARCHAR(50); 
DECLARE @CORPUserSchemaName as VARCHAR(50);
DECLARE @CORPUserMembershipName as VARCHAR(50);
DECLARE @CORPUserextendedpropertyName as NVARCHAR(250);
DECLARE @CORPUserextendedpropertyValue as NVARCHAR(250);
DECLARE @UserMappingDBName as VARCHAR(150);
DECLARE @UserMappingLoginQuery as varchar(5000);

DECLARE @ServerRoleName as VARCHAR(50);
DECLARE @ServerRoleMemberName as VARCHAR(50);

DECLARE @CORPPermissionQuery as VARCHAR(5000);

SET @CORP = 'CORP\';
SET @DBName = 'master';
SET @DBLANGUAGE = 'us_english';

DECLARE @RNHBUsersCursor as CURSOR;
DECLARE @FGHUsersCursor as CURSOR;
DECLARE @CORPUserSchemaCursor as CURSOR;
DECLARE @CORPUserMembershipCursor as CURSOR;
DECLARE @CORPUserextendedpropertyCursor as CURSOR;
DECLARE @UserMappingDBNameCursor as CURSOR;
DECLARE @UserMappingLoginCursor as CURSOR;
DECLARE @ServerRoleCursor as CURSOR;

DECLARE @CORPPermissionCursor as CURSOR;

SET @RNHBUsersCursor = CURSOR FOR SELECT name FROM @RNHBusers;
SET @FGHUsersCursor = CURSOR FOR SELECT name FROM @FGHusers;
SET @UserMappingDBNameCursor = CURSOR FOR SELECT DBname FROM @UserMappingTable;
 
OPEN @RNHBUsersCursor;
FETCH NEXT FROM @RNHBUsersCursor INTO @RNHBUserName;
 WHILE @@FETCH_STATUS = 0
BEGIN
 --PRINT @RNHBUserName;
 SET @RolName = SUBSTRING(@RNHBUserName, CHARINDEX('\', @RNHBUserName)+1, LEN(@RNHBUserName));
 SET @CORPUserName = @CORP + @RolName;
 PRINT '--CHECKING: ' + @CORPUserName

 -- CREATE LOGIN
If not Exists (select loginname from sys.syslogins where name = @CORPUserName)
Begin	
	 If Exists (select TOP 1 dbname from sys.syslogins where name = @RNHBUserName)
		 BEGIN		 
			SET @DBName = (select TOP 1 dbname from sys.syslogins  where name = @RNHBUserName);
			SET @DBLANGUAGE =  (select TOP 1 [language] from sys.syslogins  where name = @RNHBUserName);
			Select @SqlStatement = 'CREATE LOGIN ' + QUOTENAME(@CORPUserName) + ' FROM WINDOWS WITH DEFAULT_DATABASE=[' + QUOTENAME(@DBName) + '], DEFAULT_LANGUAGE=[' + QUOTENAME(@DBLANGUAGE) + ']';
			
			PRINT 'EXEC sp_executesql ' + @SqlStatement
			--EXEC sp_executesql @SqlStatement	 
		 END
	 ELSE
		BEGIN
			PRINT 'CREATE LOGIN [' + @CORPUserName + '] FROM WINDOWS'
			--CREATE LOGIN [@CORPUserName] FROM WINDOWS --CREATE CORP LOGIN			
		END
	
	-- CHECK @RNHBUserName LOGIN SERVER ROLE, IF EXIST ADD THAT TO @CORPUserName
	if Exists (	select role_principal_id from sys.server_role_members where member_principal_id = (SELECT principal_id FROM sys.server_principals WHERE NAME = @RNHBUserName))
	BEGIN
		SET @ServerRoleCursor = CURSOR FOR SELECT role.name AS RoleName, member.name AS MemberName  
											FROM sys.server_role_members  JOIN sys.server_principals AS role  
											ON sys.server_role_members.role_principal_id = role.principal_id 
											JOIN sys.server_principals AS member  ON sys.server_role_members.member_principal_id = member.principal_id	
											WHERE member.name = @RNHBUserName;
		OPEN @ServerRoleCursor;
		FETCH NEXT FROM @ServerRoleCursor INTO @ServerRoleName, @ServerRoleMemberName;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			PRINT 'ALTER SERVER ROLE [' + @ServerRoleName + '] ADD MEMBER [' + @CORPUserName + ']'
			--ALTER SERVER ROLE [@ServerRoleName] ADD MEMBER [@CORPUserName]
			FETCH NEXT FROM @ServerRoleCursor INTO @ServerRoleName, @ServerRoleMemberName;
		END
		CLOSE @ServerRoleCursor;
	END
	
	-- CHECK @RNHBUserName LOGIN USER MAPPING, IF EXIST ADD THAT TO @CORPUserName 	
	if Exists(select DBname from @UserMappingTable WHERE LoginName = @RNHBUserName)
	BEGIN
	
		SET @UserMappingDBNameCursor = CURSOR FOR select DBname from @UserMappingTable;
		OPEN @UserMappingDBNameCursor;
		FETCH NEXT FROM @UserMappingDBNameCursor INTO @UserMappingDBName;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			SET @USE_DATABASE_QUERY = N'USE ' + QUOTENAME(@UserMappingDBName);

			PRINT (@USE_DATABASE_QUERY)
			PRINT 'GO'
			--EXECUTE(@USE_DATABASE_QUERY)
				
			if Exists( SELECT * FROM sys.database_role_members WHERE member_principal_id = USER_ID(@RNHBUserName))
			BEGIN
				SET @UserMappingLoginCursor = CURSOR FOR SELECT  'ALTER ROLE [' + DP1.name + '] ADD MEMBER [' + @CORPUserName + ']' 
						FROM sys.database_role_members AS DRM  RIGHT OUTER JOIN sys.database_principals AS DP1  
						ON DRM.role_principal_id = DP1.principal_id  LEFT OUTER JOIN sys.database_principals AS DP2  
						ON DRM.member_principal_id = DP2.principal_id WHERE DP2.name = @RNHBUserName
					OPEN @UserMappingLoginCursor;
					FETCH NEXT FROM @UserMappingLoginCursor INTO @UserMappingLoginQuery;
					WHILE @@FETCH_STATUS = 0
					BEGIN
						PRINT 'EXEC sp_executesql ' + @UserMappingLoginQuery
						--EXEC sp_executesql @UserMappingLoginQuery
						FETCH NEXT FROM @UserMappingLoginCursor INTO @UserMappingLoginQuery;
					END
					CLOSE @UserMappingLoginCursor;
			END
			FETCH NEXT FROM @UserMappingDBNameCursor INTO @UserMappingDBName;
		END
		CLOSE @UserMappingDBNameCursor;
	END
	PRINT (@USE_DEFAULT_DATABASE_QUERY)
	PRINT 'GO'
	--EXECUTE(@USE_DEFAULT_DATABASE_QUERY)

	-- CHECK 


End

-- CREATE USER + koppelen met login
If not Exists (select name from sys.sysusers where name = @CORPUserName)
Begin
	PRINT 'CREATE USER [' + @CORPUserName + '] FOR LOGIN [' + @CORPUserName + ']'
	--CREATE USER [@CORPUserName] FOR LOGIN [@CORPUserName]; -- CREATE CORP USER FOR CORP LOGIN

	-- CHECK @RNHBUserName SCHEMA HERE, IF EXIST ADD THAT TO @CORPUserName
	If Exists (SELECT name FROM  sys.schemas WHERE principal_id = USER_ID(@RNHBUserName))
	BEGIN
		PRINT 'ALTER USER [' + @RNHBUserName + '] WITH DEFAULT_SCHEMA=NULL'
		--ALTER USER [@RNHBUserName] WITH DEFAULT_SCHEMA=NULL
		SET @CORPUserSchemaCursor = CURSOR FOR SELECT name FROM  sys.schemas WHERE principal_id = USER_ID(@RNHBUserName);
		OPEN @CORPUserSchemaCursor;
		FETCH NEXT FROM @CORPUserSchemaCursor INTO @CORPUserSchemaName;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			PRINT 'ALTER AUTHORIZATION ON SCHEMA::[' + @CORPUserSchemaName + '] TO [' + @CORPUserName + ']'
			--ALTER AUTHORIZATION ON SCHEMA::[@CORPUserSchemaName] TO [@CORPUserName]
			FETCH NEXT FROM @CORPUserSchemaCursor INTO @CORPUserSchemaName;
		END
		CLOSE @CORPUserSchemaCursor;
	END

	--CHECK @RNHBUserName MEMBER ROL HERE,  IF EXIST ADD THAT TO @CORPUserName 
	If Exists (select NAME from sys.database_principals A INNER JOIN sys.database_role_members B ON B.role_principal_id = A.principal_id WHERE B.member_principal_id = USER_ID(@RNHBUserName))
	BEGIN		
		SET @CORPUserMembershipCursor = CURSOR FOR select NAME from sys.database_principals A INNER JOIN sys.database_role_members B ON B.role_principal_id = A.principal_id WHERE B.member_principal_id = USER_ID(@RNHBUserName);
		OPEN @CORPUserMembershipCursor;
		FETCH NEXT FROM @CORPUserMembershipCursor INTO @CORPUserMembershipName;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			PRINT 'ALTER ROLE [' + @CORPUserMembershipName + '] ADD MEMBER [' + @CORPUserName + ']	'
			-- ALTER ROLE [@CORPUserMembershipName] ADD MEMBER [@CORPUserName]			
			FETCH NEXT FROM @CORPUserMembershipCursor INTO @CORPUserMembershipName;
		END
		CLOSE @CORPUserMembershipCursor;		
	END
	
	-- CHECK extended_properties HERE, IF EXIST ADD THAT TO @CORPUserName 
	If Exists (SELECT name, value FROM fn_listextendedproperty(default, 'USER', @RNHBUserName , default, default, default, default))
	BEGIN
		SET @CORPUserextendedpropertyCursor = CURSOR FOR SELECT name, CONVERT(nvarchar(250),value) FROM fn_listextendedproperty(default, 'USER', @RNHBUserName, default, default, default, default);
		OPEN @CORPUserextendedpropertyCursor;
		FETCH NEXT FROM @CORPUserextendedpropertyCursor INTO @CORPUserextendedpropertyName, @CORPUserextendedpropertyValue;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			PRINT 'EXEC sys.sp_addextendedproperty @name=' + @CORPUserextendedpropertyName + ', @value=' + @CORPUserextendedpropertyValue + ', @level0type=N''USER''' + ', @level0name=[' + @CORPUserName + ']'
			--EXEC sys.sp_addextendedproperty @name=@CORPUserextendedpropertyName, @value=@CORPUserextendedpropertyValue, @level0type=N'USER', @level0name=[@CORPUserName]
			FETCH NEXT FROM @CORPUserextendedpropertyCursor INTO  @CORPUserextendedpropertyName, @CORPUserextendedpropertyValue;
		END
		CLOSE @CORPUserextendedpropertyCursor;
	END

	-- CHECK USER PERMISSIONS
	if Exists (select a.class, a.TYPE, A.permission_name, A.state, a.major_id from sys.database_permissions a inner join sys.database_principals b  on a.grantee_principal_id = b.principal_id and b.name = @RNHBUserName)
	BEGIN		
		SET @CORPPermissionCursor = CURSOR FOR (SELECT 
						CASE database_permissions.state_desc
							WHEN 'DENY' THEN 'DENY ' + database_permissions.permission_name        
							ELSE 'GRANT ' + database_permissions.permission_name 
						END + 
						CASE database_permissions.class_desc
							WHEN 'DATABASE' THEN ''
							else 'ON '
						end +
						CASE database_permissions.class_desc
							WHEN 'SCHEMA' THEN 'SCHEMA::[' + schema_name(major_id) + ']'
							WHEN 'DATABASE' THEN ''
							WHEN 'ASSEMBLY' THEN 'ASSEMBLY::[Microsoft.SqlServer.Types]'                 
							WHEN 'DATABASE_PRINCIPAL' THEN 
								CASE WHEN grantor_principal_id > 1 THEN ' USER::[' + (SELECT top 1 name FROM SYS.sysusers WHERE uid= major_id ) + ']'  
								ELSE ' ROLE::[' + (SELECT top 1 name FROM SYS.sysusers WHERE uid= major_id ) + ']'  END
							WHEN 'OBJECT_OR_COLUMN' THEN '[' + schema_name(schema_id) + '].[' + object_name(major_id) + ']' COLLATE SQL_Latin1_General_CP1_CI_AS           
							ELSE '' 
						END + 
						' TO [' + database_principals.name COLLATE SQL_Latin1_General_CP1_CI_AS  + '] ' + 
						CASE database_permissions.state_desc
							WHEN 'GRANT_WITH_GRANT_OPTION' THEN ' WITH GRANT OPTION '        
							ELSE '' 
						END 
					FROM sys.database_permissions
					JOIN sys.database_principals
					ON database_permissions.grantee_principal_id = database_principals.principal_id
					LEFT JOIN sys.objects
					ON objects.object_id = database_permissions.major_id
					WHERE database_principals.name = @RNHBUserName)
		OPEN @CORPPermissionCursor;
		FETCH NEXT FROM @CORPPermissionCursor INTO @CORPPermissionQuery;
		WHILE @@FETCH_STATUS = 0
		BEGIN
			PRINT 'EXEC sp_executesql ' + @CORPPermissionQuery
			--EXEC sp_executesql @CORPPermissionQuery
	
			FETCH NEXT FROM @CORPPermissionCursor INTO @CORPPermissionQuery;
		END
		CLOSE @CORPPermissionCursor;	
	END

End

PRINT 'DROP USER [' + @RNHBUserName + ']'
--DROP USER [@RNHBUserName] --DELETE RNHB USER

 FETCH NEXT FROM @RNHBUsersCursor INTO @RNHBUserName;
END

OPEN @FGHUsersCursor;
FETCH NEXT FROM @FGHUsersCursor INTO @FGHUserName;
 WHILE @@FETCH_STATUS = 0
BEGIN
   PRINT 'DROP USER [' + @FGHUserName + ']'
 --DROP USER [@FGHUserName] --delete FGH user
 FETCH NEXT FROM @FGHUsersCursor INTO @FGHUserName;
END

CLOSE @FGHUsersCursor;
CLOSE @RNHBUsersCursor;
DEALLOCATE @FGHUsersCursor;
DEALLOCATE @RNHBUsersCursor;

--DEALLOCATE @CORPUserSchemaCursor;
--DEALLOCATE @CORPUserextendedpropertyCursor;	
--DEALLOCATE @CORPUserMembershipCursor;

--DEALLOCATE @CORPPermissionCursor;

--DEALLOCATE @ServerRoleCursor;