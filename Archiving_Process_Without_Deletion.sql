/*
Archive stored procedure, this script supports:
- Moving data from source to destination database without deletion.
- Moving data using batch size.
- Run for x minutes with auto stop counter
- Retention based on months for tables which have creation or update dates

Developer: John Restrepo

SET @WaitForVal = '00:00:02' -- WAIT SOME TIME BETWEEN BATCHES

Execution example:
EXEC Archiving_Process_Without_Deletion @BatchSize = 2000, @RetentionInMonths = 30, @MinutesToRun = 2

*/

CREATE PROCEDURE Archiving_Process_Without_Deletion
	@BatchSize INT,
	@RetentionInMonths INT,
	@MinutesToRun INT -- 0: "UNLIMITED" TIME
AS
DECLARE @TotalBatchSize INT,
		@WaitForVal VARCHAR(8), 
		@EndTime DATETIME,
		@MSG VARCHAR(500),
		@MinIDTBatch INT,
		@MaxIDTBatch INT,
		@RowsCopiedToProcessTable INT = 0,
		@RetentionDate DATE = DATEADD(MONTH,-1 * @RetentionInMonths,GETUTCDATE())

DECLARE @SQL NVARCHAR(MAX) = ''

DECLARE @Batches AS TABLE (
	[Id] INT IDENTITY,
	[IdCount] INT,
	[StartDate] DATETIME,
	[EndDate] DATETIME
);

BEGIN TRY
	IF OBJECT_ID('tempdb..#tmpTableToMove') IS NOT NULL DROP TABLE #tmpTableToMove
	CREATE TABLE #tmpTableToMove (ProcessId INT NOT NULL)

	CREATE UNIQUE CLUSTERED INDEX [IX_tmpTableToMove_ProcessId] ON #tmpTableToMove
	(
		[ProcessId]
	)

	SET NOCOUNT ON
	SET XACT_ABORT ON
	SET DEADLOCK_PRIORITY LOW;

	/* Start Params Section */

	SET @WaitForVal = '00:00:02' -- WAIT X TIME BETWEEN BATCHES

	/* Finish Params Section */

	SET @EndTime = CASE WHEN @MinutesToRun = 0 THEN DATEADD(YEAR, 3, GETDATE()) ELSE DATEADD(MINUTE, @MinutesToRun, GETDATE()) END
	SET @RowsCopiedToProcessTable = @BatchSize

	WHILE (@EndTime > GETDATE() AND @RowsCopiedToProcessTable = @BatchSize)
		BEGIN
			TRUNCATE TABLE #tmpTableToMove

			INSERT INTO #tmpTableToMove (ProcessId)
			SELECT TOP (@BatchSize) ST.ID
			FROM TableToMove ST
				LEFT JOIN DESTINATION_DATABASE.dbo.TableToMove DT ON DT.ID = ST.ID 
			WHERE ST.DateUpdated <= @RetentionDate AND DT.ID IS NULL

			SET @TotalBatchSize = @@rowcount
			
			SET @MSG = (CONVERT( VARCHAR(24), GETDATE(), 121)) + ': Start Moving, Total records to move: ' + CAST(@TotalBatchSize AS VARCHAR)
			RAISERROR (@MSG, 0, 1) WITH NOWAIT
		
			IF ISNULL(@TotalBatchSize,0) > 0
				BEGIN
					INSERT INTO @Batches ([IdCount],[StartDate],[EndDate])
					SELECT @TotalBatchSize, GETDATE(), NULL

					BEGIN TRY
						BEGIN TRANSACTION	
							-- Move dependent tables data, repeat for each table
							INSERT INTO DESTINATION_DATABASE.dbo.tblWOPM (Field1, Field2, Field3)
							SELECT Field1, Field2, Field3
							FROM DependentTable
								INNER JOIN #tmpTableToMove ON ID = ProcessId
							
							
							-- Move final table
							INSERT INTO DESTINATION_DATABASE.dbo.TableToMove (Field1, Field2, Field3)
							SELECT Field1, Field2, Field3
							FROM DestinationTable
								INNER JOIN #tmpTableToMove ON ID = ProcessId

							SET @RowsCopiedToProcessTable = @TotalBatchSize;

							SET @MSG = (CONVERT( VARCHAR(24), GETDATE(), 121)) + ': Moving process finished, Total records moved: ' + CAST(@TotalBatchSize AS VARCHAR)
							RAISERROR (@MSG, 0, 1) WITH NOWAIT

						COMMIT TRANSACTION

					END TRY
					BEGIN CATCH
						IF @@trancount > 0
							BEGIN 
								ROLLBACK TRANSACTION
							END

						SET @MSG = '*** Error processing batch, Details: ' + ERROR_MESSAGE() + ' ***'
						RAISERROR (@MSG, 16, 1) WITH NOWAIT
					END CATCH						

					UPDATE @Batches
					SET EndDate = GETDATE()
					WHERE EndDate IS NULL 
				END
			ELSE 
				BEGIN
					SET @RowsCopiedToProcessTable = 0
				END

			WAITFOR DELAY @WaitForVal 			
		END

	IF OBJECT_ID('tempdb..#tmpTableToMove') IS NOT NULL DROP TABLE #tmpTableToMove

	SELECT * FROM @Batches
END TRY
BEGIN CATCH
	SET @MSG = ERROR_MESSAGE()
	RAISERROR (@MSG, 16, 1) WITH NOWAIT
END CATCH