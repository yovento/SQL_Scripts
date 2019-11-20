/* 
---------------------------------------------------------------------------------------------------------------------------------------- 
Author : Bharat Panthee

Name of the Procedure : GenerateInsertStatement
---------------------------------------------------------------------------------------------------------------------------------------- 
Purpose :This Procedure is used generate Insert  scripts for a table 
---------------------------------------------------------------------------------------------------------------------------------------- 
---------------------------------------------------------------------------------------------------------------------------------------- 
 Expected Output : Generate script for Insert statement for given range of values
---------------------------------------------------------------------------------------------------------------------------------------- */ 


	set nocount on
	--==============================
	-- Variables para ejecución
	Declare @strRange varchar(20),@fnlRange varchar(20),@TableName varchar(300)
	Set @strRange = 1 --Valor de la columna identificadora inicial
	Set @fnlRange = 1000 --Valor de la columna identificadora inicial 
	Set @TableName = 'tblEspecies' --Tabla de donde se van a generar los inserts
	
	Declare @sqlStatement varchar(2000)
	Declare @insertStatementColumnName varchar(8000)
	Declare @insertStatement nvarchar(max)
	Declare @Fetchvalue varchar(2000)
	Declare @col_Name varchar(500)
	Declare @tempcol_Name varchar(500)
	Declare @data_type varchar(100)
	Declare @tempdata_type varchar(100)
	Declare @Primary_col_Name varchar(500)
	Declare @Primaryid int
	
	if object_id('tempdb..##col_name_col','U') IS NOT NULL
	drop table ##col_name_col
		if object_id('tempdb..##fetchvalue','U') IS NOT NULL
	drop table ##fetchvalue
				
	Create table ##col_name_col(column_name varchar(500), data_type varchar(100))

	Declare column_col cursor for select Column_name,data_type from information_schema.columns where table_name = @TableName order by ordinal_position asc
	open column_col

	fetch next from column_col into @col_Name,@data_type
	set @Primary_col_Name = @col_Name
	if not exists(select [object_id] from sys.columns where [name] =  @col_Name and column_id = 1 and is_identity =1)
	begin
		set @insertStatementColumnName = @col_Name
		insert into ##col_name_col values(@col_Name,@data_type)
	end
	else 
		set @insertStatementColumnName = ''

	fetch next from column_col into @col_Name,@data_type
	while @@fetch_status =0
	begin
		if @insertStatementColumnName = ''
			set @insertStatementColumnName = @col_Name
		else
			set @insertStatementColumnName = @insertStatementColumnName + ',' + @col_Name 

		insert into ##col_name_col values(@col_Name,@data_type)
		fetch next from column_col into @col_Name,@data_type
	end
	close column_col
	deallocate column_col
	set @sqlStatement = ' declare rec_col cursor for Select ' + @Primary_col_Name + ' from ' + @TableName + '  where  ' + @Primary_col_Name + ' between ' + @strRange + ' and ' + @fnlRange
	exec (@sqlStatement)
	open rec_col
	fetch next from rec_col into @Primaryid
	While @@fetch_status = 0 
	begin
		Declare column_col cursor for select * from ##col_name_col
		open column_col
		fetch next from column_col into @tempcol_Name,@tempdata_type
		set @insertStatement = 'insert into ' + @TableName + '(' + @insertStatementColumnName + ') Values ('
		while @@fetch_status = 0
		BEGIN
			exec ('select ' + @tempcol_Name + ' into ##fetchvalue from ' + @TableName + ' where ' + @Primary_col_Name + ' = ' + @Primaryid )
			--print @tempcol_Name
			if @tempdata_type = 'datetime' or @tempdata_type='numeric' 
				set @Fetchvalue = cast ((select * from ##fetchvalue) as varchar(100))
			else 
			begin	
				set @Fetchvalue = (select * from ##fetchvalue)
			end
			if isnull(@Fetchvalue,'') = '' 
				set @Fetchvalue = 'NULL'
			drop table ##fetchvalue
			set @Fetchvalue = ltrim(rtrim(@Fetchvalue))
			if @tempdata_type = 'int' or @tempdata_type='numeric' 
			begin
			if right(@insertStatement,8)	= 'Values ('
				set	@insertStatement = @insertStatement + '' + @Fetchvalue
			else
				set	@insertStatement = @insertStatement + ',' + @Fetchvalue
			end
			else
			BEGIN	
				if @Fetchvalue = 'NULL'
				BEGIN
					if right(@insertStatement,8)	= 'Values ('
						set	@insertStatement = @insertStatement + '' + @Fetchvalue
					else
						set	@insertStatement = @insertStatement + ',' + @Fetchvalue
				END	
				else 
				begin
					if right(@insertStatement,8)	= 'Values ('	
						set	@insertStatement = @insertStatement + '''' + @Fetchvalue + ''''
					else
						set	@insertStatement = @insertStatement + ',''' + @Fetchvalue + ''''
				end	
			END
			fetch next from column_col into @tempcol_Name,@tempdata_type
		END
		set @insertStatement = @insertStatement + ')'
		close column_col
		deallocate column_col
		print @insertStatement
		set @insertStatement = ''
		fetch next from rec_col into @Primaryid
	end
	close rec_col
	deallocate rec_col
	--select * from  ##col_name_col
	drop table ##col_name_col
