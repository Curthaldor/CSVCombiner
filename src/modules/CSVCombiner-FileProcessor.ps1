# ==============================================================================
# CSV Combiner File Processing Module v2.4
# ==============================================================================
# Purpose: Specialized CSV file processing and merging operations
# ==============================================================================

class CSVFileProcessor {
    [object]$Config
    [object]$Logger
    
    CSVFileProcessor([object]$config, [object]$logger) {
        $this.Config = $config
        $this.Logger = $logger
    }
    
    # Main entry point for processing CSV files
    [string]ProcessFiles([string]$inputFolder, [object]$changes = $null) {
        try {
            $csvFiles = @(Get-ChildItem -Path $inputFolder -Filter "*.csv" -File)
            $outputPath = $this.GetOutputPath()
            
            # Analyze current state
            $currentState = $this.AnalyzeCurrentState($outputPath)
            
            # Determine files to process
            $filesToProcess = $this.DetermineFilesToProcess($csvFiles, $currentState, $changes)
            
            if ($filesToProcess.Count -eq 0) {
                $this.Logger.Info("No files to process")
                return $outputPath
            }
            
            # Handle modified files (remove existing data)
            $this.HandleModifiedFiles($outputPath, $changes, $currentState)
            
            # Process new data
            $newData = $this.ProcessInputFiles($filesToProcess)
            
            if ($newData.Count -eq 0) {
                $this.Logger.Info("No new data to process")
                return $outputPath
            }
            
            # Merge and save
            $success = $this.MergeAndSaveData($outputPath, $newData, $currentState)
            
            if ($success) { return $outputPath } else { return $null }
        }
        catch {
            $this.Logger.Error("Error in file processing: $($_.Exception.Message)")
            return $null
        }
    }
    
    [string]GetOutputPath() {
        $outputDir = $this.Config.GetOutputFolder()
        $baseName = $this.Config.GetOutputBaseName()
        return Join-Path $outputDir ($baseName + ".csv")
    }
    
    [hashtable]AnalyzeCurrentState([string]$outputPath) {
        $state = @{
            FileExists = Test-Path $outputPath
            Schema = @()
            RowCount = 0
            ProcessedFiles = @()
        }
        
        if ($state.FileExists) {
            $state.Schema = Get-MasterFileSchema -MasterFilePath $outputPath
            $state.RowCount = Get-MasterFileRowCount -MasterFilePath $outputPath
            $state.ProcessedFiles = Get-ProcessedFilenames -MasterFilePath $outputPath
            
            if ($state.RowCount -gt 0) {
                $this.Logger.Info("Existing master has $($state.RowCount) rows with $($state.Schema.Count) columns")
                $this.Logger.Info("Found $($state.ProcessedFiles.Count) processed files")
            }
            else {
                $this.Logger.Warning("Master file exists but is empty - will recreate")
                $state.FileExists = $false
            }
        }
        else {
            $this.Logger.Info("No output file found - will create new master file")
        }
        
        return $state
    }
    
    [System.Collections.ArrayList]DetermineFilesToProcess([object[]]$csvFiles, [hashtable]$currentState, [object]$changes) {
        $filesToProcess = [System.Collections.ArrayList]::new()
        
        # Ensure csvFiles is never null
        if ($null -eq $csvFiles) { $csvFiles = @() }
        
        if ($null -eq $changes) {
            # Initial run - find unprocessed files
            if ($currentState.FileExists -and $currentState.ProcessedFiles.Count -gt 0) {
                foreach ($file in $csvFiles) {
                    if ($currentState.ProcessedFiles -notcontains $file.Name) {
                        [void]$filesToProcess.Add($file)
                    }
                }
                
                if ($filesToProcess.Count -gt 0) {
                    $this.Logger.Info("Found $($filesToProcess.Count) unprocessed files out of $($csvFiles.Count) total")
                }
                else {
                    $this.Logger.Info("All $($csvFiles.Count) input files are already processed")
                }
            }
            else {
                # No master file - process all
                if ($csvFiles -and $csvFiles.Count -gt 0) {
                    foreach ($file in $csvFiles) {
                        [void]$filesToProcess.Add($file)
                    }
                    $this.Logger.Info("Initial processing: Processing all $($csvFiles.Count) CSV files")
                }
                else {
                    $this.Logger.Info("No CSV files found in input directory")
                }
            }
        }
        else {
            # Monitoring mode - process changed files
            foreach ($fileName in ($changes.NewFiles + $changes.ModifiedFiles)) {
                $file = $csvFiles | Where-Object { $_.Name -eq $fileName }
                if ($file) {
                    [void]$filesToProcess.Add($file)
                }
            }
            $this.Logger.Info("Additive update: Processing $($filesToProcess.Count) changed files")
        }
        
        return $filesToProcess
    }
    
    [void]HandleModifiedFiles([string]$outputPath, [object]$changes, [hashtable]$currentState) {
        if ($null -eq $changes -or $changes.ModifiedFiles.Count -eq 0 -or $currentState.RowCount -eq 0) {
            return
        }
        
        $this.Logger.Info("Removing data from $($changes.ModifiedFiles.Count) modified files")
        $removeSuccess = Remove-RowsFromMasterFile -MasterFilePath $outputPath -TimestampsToRemove $changes.ModifiedFiles
        
        if ($removeSuccess) {
            $newRowCount = Get-MasterFileRowCount -MasterFilePath $outputPath
            $this.Logger.Info("After removal: $newRowCount rows remain")
        }
        else {
            $this.Logger.Warning("Failed to remove modified file data, proceeding with append")
        }
    }
    
    [System.Collections.ArrayList]ProcessInputFiles([System.Collections.ArrayList]$filesToProcess) {
        $dataColumns = [System.Collections.Generic.HashSet[string]]::new()
        $newDataRows = [System.Collections.ArrayList]::new()
        
        foreach ($csvFile in $filesToProcess) {
            $fileData = $this.ProcessSingleFile($csvFile)
            
            if ($fileData.Rows.Count -gt 0) {
                # Collect columns
                foreach ($column in $fileData.Columns) {
                    [void]$dataColumns.Add($column)
                }
                
                # Add rows with timestamp
                foreach ($row in $fileData.Rows) {
                    [void]$newDataRows.Add(@{
                        Row = $row
                        SourceFile = $csvFile.Name
                    })
                }
            }
        }
        
        $this.Logger.Info("Collected $($newDataRows.Count) rows from $($dataColumns.Count) unique columns")
        return $newDataRows
    }
    
    [hashtable]ProcessSingleFile([System.IO.FileInfo]$csvFile) {
        $result = @{
            Rows = @()
            Columns = @()
        }
        
        try {
            $this.Logger.Info("Processing: $($csvFile.Name)")
            
            # Validate filename format
            if (!(Test-FilenameFormat -FileName $csvFile.Name -ValidateFormat $this.Config.GetValidateFilenameFormat())) {
                $this.Logger.Warning("Skipping file with invalid format: $($csvFile.Name)")
                return $result
            }
            
            # Check file content
            $fileContent = Get-Content -Path $csvFile.FullName -Raw
            if ([string]::IsNullOrWhiteSpace($fileContent)) {
                $this.Logger.Warning("Skipping empty file: $($csvFile.Name)")
                return $result
            }
            
            # Process CSV with duplicate column handling
            $csvData = $this.ImportCSVWithUniqueHeaders($csvFile.FullName)
            
            if ($csvData.Count -gt 0) {
                $result.Rows = $csvData
                $result.Columns = $csvData[0].PSObject.Properties.Name
                $this.Logger.Debug("Successfully processed $($csvData.Count) rows with $($result.Columns.Count) columns")
            }
        }
        catch {
            $this.Logger.Error("Error processing $($csvFile.Name): $($_.Exception.Message)")
        }
        
        return $result
    }
    
    [object[]]ImportCSVWithUniqueHeaders([string]$filePath) {
        $lines = Get-Content -Path $filePath
        
        if ($lines.Count -eq 0 -or [string]::IsNullOrWhiteSpace($lines[0])) {
            throw "File has no header line"
        }
        
        # Handle duplicate column names
        $headerLine = $lines[0]
        $columnNames = $headerLine -split ','
        $uniqueColumnNames = $this.CreateUniqueColumnNames($columnNames)
        
        # Create temporary CSV with unique headers
        $tempCsvContent = @()
        $tempCsvContent += $uniqueColumnNames -join ','
        
        for ($i = 1; $i -lt $lines.Count; $i++) {
            $tempCsvContent += $lines[$i]
        }
        
        # Import via temporary file
        $tempFile = [System.IO.Path]::GetTempFileName() + ".csv"
        try {
            $tempCsvContent | Out-File -FilePath $tempFile -Encoding UTF8
            return Import-Csv -Path $tempFile
        }
        finally {
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
            }
        }
    }
    
    [string[]]CreateUniqueColumnNames([string[]]$columnNames) {
        $uniqueNames = @()
        $columnCounts = @{}
        
        foreach ($columnName in $columnNames) {
            $trimmedName = $columnName.Trim()
            if ($columnCounts.ContainsKey($trimmedName)) {
                $columnCounts[$trimmedName]++
                $uniqueName = "${trimmedName}_$($columnCounts[$trimmedName])"
            }
            else {
                $columnCounts[$trimmedName] = 1
                $uniqueName = $trimmedName
            }
            $uniqueNames += $uniqueName
        }
        
        return $uniqueNames
    }
    
    [bool]MergeAndSaveData([string]$outputPath, [System.Collections.ArrayList]$newDataRows, [hashtable]$currentState) {
        try {
            # Create unified schema
            $newColumns = [string[]]($newDataRows[0].Row.PSObject.Properties.Name | Sort-Object)
            $allColumns = Merge-ColumnSchemas -ExistingColumns $currentState.Schema -NewColumns $newColumns
            
            $this.Logger.Info("Unified schema contains $($allColumns.Count) columns")
            
            # Convert to unified format
            $unifiedData = $this.ConvertToUnifiedFormat($newDataRows, $allColumns)
            
            # Remove duplicates
            $excludeColumns = @("SourceFile")
            $unifiedData = Remove-DuplicateRows -Data $unifiedData -ExcludeColumns $excludeColumns
            
            $this.Logger.Info("Processed $($unifiedData.Count) unique rows (removed $($newDataRows.Count - $unifiedData.Count) duplicates)")
            
            # Save to file
            $createNewFile = (-not $currentState.FileExists) -or ($currentState.Schema.Count -eq 0)
            $success = Append-ToMasterFile -MasterFilePath $outputPath -NewData $unifiedData -UnifiedSchema $allColumns -CreateNewFile $createNewFile
            
            if ($success) {
                $finalRowCount = Get-MasterFileRowCount -MasterFilePath $outputPath
                $this.Logger.Info("Successfully updated master file: $outputPath ($finalRowCount total rows)")
            }
            
            return $success
        }
        catch {
            $this.Logger.Error("Error in merge and save: $($_.Exception.Message)")
            return $false
        }
    }
    
    [System.Collections.ArrayList]ConvertToUnifiedFormat([System.Collections.ArrayList]$dataRows, [string[]]$allColumns) {
        $unifiedData = [System.Collections.ArrayList]::new()
        
        foreach ($dataItem in $dataRows) {
            $unifiedRow = New-UnifiedRow -SourceRow $dataItem.Row -UnifiedSchema $allColumns -SourceFileValue $dataItem.SourceFile
            [void]$unifiedData.Add($unifiedRow)
        }
        
        return $unifiedData
    }
}
