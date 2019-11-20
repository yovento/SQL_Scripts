USE MASTER
GO

SET NOCOUNT ON;

SELECT ROW_NUMBER() OVER(ORDER BY name) Seq, name Banco
INTO #Databases
FROM sys.databases
WHERE name NOT IN ('master', 'model', 'msdb', 'tempdb', 'ReportServerTempDB')
AND compatibility_level > 80 and state = 0
ORDER BY Banco;

Select * from #Databases

DECLARE
	@Loop INT = 1,
	@Qt INT = (SELECT COUNT(1) FROM #Databases),
	@Banco VARCHAR(50);

	WHILE @Loop <= @Qt
	 BEGIN
	  SET @Banco = (SELECT Banco FROM #Databases WHERE Seq = @Loop);
		EXEC( 
		'USE ' + @Banco + '; ' +
		'PRINT ''Database em uso: '' + db_name();
		SELECT
			ROW_NUMBER() OVER(ORDER BY p.object_id, p.index_id) Seq,
   			t.name Tabela, h.name Esquema,
			i.name Indice, p.avg_fragmentation_in_percent Frag
		INTO #Consulta
		FROM
		sys.dm_db_index_physical_stats(DB_ID(),null,null,null,null) p
		join sys.indexes i on (p.object_id = i.object_id and p.index_id = i.index_id)
		join sys.tables t on (p.object_id = t.object_id)
		join sys.schemas h on (t.schema_id = h.schema_id)
		where p.avg_fragmentation_in_percent > 10.0
		and p.index_id > 0
		and p.page_count >= 10
		ORDER BY Esquema, Tabela;
		DECLARE
			@Loop INT = 1,
			@Total INT = (SELECT COUNT(1) FROM #Consulta),
			@Comando VARCHAR(500)
		WHILE @Loop <= @Total
			BEGIN
				SELECT @Comando = ''ALTER INDEX '' + Indice +
					'' ON '' + Esquema + ''.'' + Tabela +
					( CASE WHEN Frag > 30.0 THEN '' REBUILD'' ELSE '' REORGANIZE'' END)
					FROM #Consulta
					WHERE Seq = @Loop;
				
				EXEC(@Comando);
				PRINT ''Executado: '' + @Comando;
				SET @Loop = @Loop + 1;
			END;
		PRINT DB_NAME() + '' Qtde de índices afetados: '' + CONVERT(VARCHAR(5),@Total);
		PRINT ''-----'';
		DROP TABLE #Consulta;');  
	  SET @Loop = @Loop + 1;
	 END;

DROP TABLE #Databases;