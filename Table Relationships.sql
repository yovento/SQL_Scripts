Declare @strNombreTabla varchar(100)

Set @strNombreTabla = 'tblPaises' --Especifique el nombre de la tabla

------------
-- Con que esta relacionada la tabla
select OBP.name, COBP.name, OBR.name, COBR.name
from sys.foreign_key_columns FK
	inner join sys.all_objects OBR on OBR.object_id = FK.referenced_object_id
	inner join sys.all_columns COBR on OBR.object_id = COBR.object_id And FK.referenced_column_id = COBR.Column_id
	inner join sys.all_objects OBP on OBP.object_id = FK.parent_object_id
	inner join sys.all_columns COBP on OBP.object_id = COBP.object_id And FK.parent_column_id = COBP.Column_id
Where FK.parent_object_id = (Select object_id From sys.all_objects Where Name = @strNombreTabla)

------------
-- Tablas relacionadas con la tabla
select OBP.name, COBP.name, OBR.name, COBR.name
from sys.foreign_key_columns FK
	inner join sys.all_objects OBR on OBR.object_id = FK.referenced_object_id
	inner join sys.all_columns COBR on OBR.object_id = COBR.object_id And FK.referenced_column_id = COBR.Column_id
	inner join sys.all_objects OBP on OBP.object_id = FK.parent_object_id
	inner join sys.all_columns COBP on OBP.object_id = COBP.object_id And FK.parent_column_id = COBP.Column_id
Where OBR.object_id = (Select object_id From sys.all_objects Where Name = @strNombreTabla)