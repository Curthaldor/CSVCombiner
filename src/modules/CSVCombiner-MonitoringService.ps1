# ==============================================================================
# CSV Combiner Monitoring Service Module v2.4
# ==============================================================================
# Purpose: File monitoring and change detection service
# ==============================================================================

class CSVMonitoringService {
    [object]$Config
    [object]$Logger
    [object]$FileProcessor
    [hashtable]$LastSnapshot
    [string]$InputFolder
    
    CSVMonitoringService([object]$config, [object]$logger, [object]$fileProcessor) {
        $this.Config = $config
        $this.Logger = $logger
        $this.FileProcessor = $fileProcessor
        $this.InputFolder = $config.GetInputFolder()
        $this.LastSnapshot = @{}
    }
    
    [void]InitializeMonitoring() {
        $this.Logger.LogSubsectionHeader("Initializing File Monitoring")
        
        # Convert paths for Windows compatibility
        $windowsPath = $this.InputFolder -replace "/", "\"
        $this.Logger.Info("Monitoring folder: $windowsPath")
        
        # Log configuration
        $this.LogMonitoringConfiguration()
        
        # Take initial snapshot
        $this.TakeInitialSnapshot()
        
        $this.Logger.Info("CSV Combiner is now running in polling mode")
        $this.Logger.Info("Press Ctrl+C to stop the script")
    }
    
    [void]LogMonitoringConfiguration() {
        $pollingInterval = $this.Config.GetPollingInterval()
        $useFileHashing = $this.Config.GetUseFileHashing()
        $waitTime = $this.Config.GetWaitForStableFile()
        
        $this.Logger.Info("Polling interval: ${pollingInterval} seconds")
        $this.Logger.Info("File hashing enabled: $useFileHashing")
        $this.Logger.Info("File stability wait time: ${waitTime}ms")
    }
    
    [void]TakeInitialSnapshot() {
        $useFileHashing = $this.Config.GetUseFileHashing()
        $validateFormat = $this.Config.GetValidateFilenameFormat()
        
        $this.LastSnapshot = Get-FileSnapshot -FolderPath $this.InputFolder -UseFileHashing $useFileHashing -ValidateFilenameFormat $validateFormat
        $this.Logger.Debug("Initial file snapshot taken")
    }
    
    [void]StartMonitoring() {
        $this.Logger.LogSubsectionHeader("Starting Monitoring Loop")
        $pollingInterval = $this.Config.GetPollingInterval()
        $loopCount = 0
        
        while ($true) {
            $loopCount++
            $this.Logger.Debug("Starting polling cycle #$loopCount")
            
            try {
                # Wait for polling interval
                Start-Sleep -Seconds $pollingInterval
                
                # Check for changes
                $changes = $this.CheckForChanges()
                
                if ($changes.HasChanges) {
                    $this.ProcessDetectedChanges($changes)
                }
                else {
                    $this.Logger.Debug("No changes detected, continuing to next cycle")
                }
            }
            catch {
                $this.Logger.Error("Exception during polling cycle: $($_.Exception.Message)")
                $this.Logger.Debug("Stack trace: $($_.ScriptStackTrace)")
                # Continue monitoring even if one cycle fails
            }
        }
    }
    
    [object]CheckForChanges() {
        $this.Logger.Debug("Taking new file snapshot and comparing changes")
        
        $useFileHashing = $this.Config.GetUseFileHashing()
        $validateFormat = $this.Config.GetValidateFilenameFormat()
        
        $snapshotStartTime = Get-Date
        $currentSnapshot = Get-FileSnapshot -FolderPath $this.InputFolder -UseFileHashing $useFileHashing -ValidateFilenameFormat $validateFormat
        $snapshotDuration = (Get-Date) - $snapshotStartTime
        $this.Logger.Debug("Snapshot took $($snapshotDuration.TotalSeconds) seconds")
        
        $compareStartTime = Get-Date
        $changes = Compare-FileSnapshots -OldSnapshot $this.LastSnapshot -NewSnapshot $currentSnapshot -ValidateFilenameFormat $validateFormat
        $compareDuration = (Get-Date) - $compareStartTime
        $this.Logger.Debug("Comparison took $($compareDuration.TotalSeconds) seconds")
        
        # Also check if output file exists - if not, force processing
        $outputFilePath = $this.FileProcessor.GetOutputPath()
        $outputFileExists = Test-Path $outputFilePath
        
        if (-not $outputFileExists) {
            $this.Logger.Info("Output file does not exist, forcing reprocessing")
            # Force processing by adding to change counts
            $changes.NewFiles += "FORCE_REPROCESS_MISSING_OUTPUT"
            $changes.Details += "Output file missing: $outputFilePath"
        }
        
        # Recalculate HasChanges to include our forced change
        $changes.HasChanges = ($changes.NewFiles.Count -gt 0 -or $changes.ModifiedFiles.Count -gt 0 -or $changes.DeletedFiles.Count -gt 0)
        
        $this.Logger.Debug("HasChanges: $($changes.HasChanges)")
        
        return $changes
    }
    
    [void]ProcessDetectedChanges([object]$changes) {
        $this.Logger.Info("File changes detected!")
        
        # Log change details
        foreach ($detail in $changes.Details) {
            $this.Logger.Info("  $detail")
        }
        
        # Wait for file stability
        $this.WaitForFileStability()
        
        # Process the changes
        $this.Logger.Info("Performing additive update based on detected changes")
        $outputPath = $this.FileProcessor.ProcessFiles($this.InputFolder, $changes)
        
        if ($outputPath) {
            $this.Logger.Info("Additive update complete: $outputPath")
        }
        else {
            $this.Logger.Warning("No changes to process during additive update")
        }
        
        # Update snapshot after successful processing
        $this.UpdateSnapshotAfterProcessing()
    }
    
    [void]WaitForFileStability() {
        $csvFiles = Get-ChildItem -Path $this.InputFolder -Filter "*.csv" -File
        $waitTime = $this.Config.GetWaitForStableFile()
        $maxRetries = $this.Config.GetMaxPollingRetries()
        $validateFormat = $this.Config.GetValidateFilenameFormat()
        
        $null = Wait-ForFileStability -CsvFiles $csvFiles -WaitTime $waitTime -MaxRetries $maxRetries -ValidateFilenameFormat $validateFormat
    }
    
    [void]UpdateSnapshotAfterProcessing() {
        $useFileHashing = $this.Config.GetUseFileHashing()
        $validateFormat = $this.Config.GetValidateFilenameFormat()
        
        $this.LastSnapshot = Get-FileSnapshot -FolderPath $this.InputFolder -UseFileHashing $useFileHashing -ValidateFilenameFormat $validateFormat
        $this.Logger.Debug("Snapshot updated after processing")
    }
}
