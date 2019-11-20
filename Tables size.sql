DECLARE @tableName VARCHAR(1000); 
CREATE TABLE #AllTables
  (
     row_num    INT IDENTITY(1, 1),
     table_name VARCHAR(1000)
  );

--Using temp table, i dont like to use cursors
INSERT INTO #AllTables
            (table_name)
SELECT [name]
FROM   sys.Tables
WHERE  [schema_id] = 1 --Only dbo tables ;

CREATE TABLE #TempTable
  (
     tableName  VARCHAR(100),
     [rows]     VARCHAR(100),
     reserved   VARCHAR(50),
     data       VARCHAR(50),
     index_size VARCHAR(50),
     unused     VARCHAR(50)
  )

DECLARE @i INT = 1;
DECLARE @tableCount INT = (SELECT COUNT(1) FROM   #AllTables );

--Loop to get all tables
WHILE ( @i <= @tableCount )
  BEGIN
      SELECT @tableName = table_name
      FROM   #AllTables
      WHERE  row_num = @i;

      --Dump the results of the sp_spaceused query to the temp table
      INSERT #TempTable
      EXEC sp_spaceused @tableName;

      SET @i = @i + 1;
  END;

--Select all records so we can use the reults
SELECT *
FROM   #TempTable
ORDER  BY data DESC;

--Final cleanup!
DROP TABLE #TempTable

DROP TABLE #Alltables; 
