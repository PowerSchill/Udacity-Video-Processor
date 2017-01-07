


<#
.SYNOPSIS
    Short description
.DESCRIPTION
    Long description
.EXAMPLE
    Example of how to use this cmdlet
.EXAMPLE
    Another example of how to use this cmdlet
#>
#function verb-noun {
[CmdletBinding()]
[OutputType([void])]
param(

)

begin {

    function Get-Platform() {
        if ( $PSVersionTable.PSVersion.Major -ge 6){
            if ( $ISWindows) { return 'Windows' }
            elseif ( $IsOSX) { return 'MacOS' }
            elseif ( $IsLinux ) { return = 'Linux' }
        }
            else {
            return 'Windows'
        }
    }
}

process {

    $SourceFolder = Resolve-Path "$PSScriptRoot/../src"
    $OutputFolder = Resolve-Path "$PSScriptRoot/../out"
    $TempFolder = Resolve-Path "$PSScriptRoot/../tmp"

    switch (Get-Platform){
        'Windows' {
            $FFMPEG = Resolve-Path "$PSScriptRoot/ffmpeg.exe"
            $FFPROBE = Resolve-Path "$PSScriptRoot/ffprobe.exe"
        }
        'MacOS' {
            $FFMPEG = Resolve-Path "$PSScriptRoot/ffmpeg"
            $FFPROBE = Resolve-Path "$PSScriptRoot/ffprobe"
        }
    }


    Get-ChildItem $SourceFolder -Directory | ForEach-Object {
        $CourseName = $_

        Write-Verbose "Processing Course: $CourseName"

        Remove-Item $TempFolder/$CourseName -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $OutputFolder/$CourseName -Recurse -Force -ErrorAction SilentlyContinue
        New-Item -ItemType Directory -Path $OutputFolder/$CourseName -Force | Out-Null

        Get-ChildItem $SourceFolder/$CourseName -Directory | ForEach-Object {
            $SectionName = $_
            Write-Verbose "`tProcessing Section: $SectionName"

            New-Item -ItemType Directory -Path $TempFolder/$CourseName/$SectionName -Force | Out-Null

            # Pull out lesson number
            $Season = $Episode = 0
            if ($SectionName -match '^P(?<Season>\d*)L(?<Episode>\d*)') {
                $Season = $Matches['Season']
                $Episode = $Matches['Episode']
            }
            elseif ($SectionName -match '^L(?<Episode>\d*)') {
                $Season = 1
                $Episode = $Matches['Episode']
            }


            $Metadata = ";FFMETADATA1`n"
            $Metadata += "title=$SectionName`n"
            $Metadata += "show=$($Coursename -replace 'Videos', '')`n"
            $Metadata += "season_number=$Season`n"
            $Metadata += "episode_sort=$Episode`n"
            $Metadata += "genre=Educational`n"
            $Metadata += "major_brand=isom`n"
            $Metadata += "compatible_brands=isomiso2avc1mp41`n"
            $Metadata += "`n"


            $CurrentDuration = 0

            Get-ChildItem $SourceFolder/$CourseName/$SectionName -File | ForEach-Object {
                $FileName = $_
                $FilePath = Resolve-Path "$SourceFolder/$CourseName/$SectionName/$_"

                Write-Verbose "`t`tProcessing File: $FileName"

                $Process     = New-Object System.Diagnostics.Process
                $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo

                $ProcessInfo.FileName               = $FFPROBE
                $ProcessInfo.Arguments              = "-v quiet -print_format compact=print_section=0:nokey=1:escape=csv -show_entries format=duration `"$FilePath`""
                $ProcessInfo.RedirectStandardOutput = $True
                $ProcessInfo.UseShellExecute        = $False

                $Process.StartInfo = $ProcessInfo
                $Process.Start() | Out-Null
                $Process.WaitForExit()

                $Duration = [math]::Round($Process.StandardOutput.ReadToEnd())*1000

                $Metadata += "[CHAPTER]`n"
                $Metadata += "TIMEBASE=1/1000`n"
                $Metadata += "START=$CurrentDuration`n"
                $Metadata += "END=$($CurrentDuration + $Duration)`n"
                $Metadata += "TITLE=$($FileName -replace '.mp4', '')`n"

                $CurrentDuration += $Duration

                $ProcessArguments = @{
                    FilePath = "$FFMPEG"
                    ArgumentList = @(
                        "-i `"$SourceFolder/$CourseName/$SectionName/$FileName`"",
                        "-c copy",
                        "-bsf:v h264_mp4toannexb",
                        "-f mpegts",
                        "`"$TempFolder/$CourseName/$SectionName/$FileName.ts`""
                    )
                    Wait = $True
                    RedirectStandardError = "/dev/null"
                    NoNewWindow = $True

                }
               Start-Process @ProcessArguments


            }

           # Populate MetaData
           $MetadataFileName = "$TempFolder/$CourseName/$($SectionName -replace ':','').ini"
           Set-Content -Path $MetadataFileName -Value $Metadata

            # Concatentate files
            $FileList=""
            Get-ChildItem $TempFolder/$CourseName/$SectionName -File | ForEach-Object {
                $FileList += "$($_.FullName)|"
            }
            $FileList = $FileList.TrimEnd("|")

            $ProcessArguments = @{
                FilePath = "$FFMPEG"
                ArgumentList = @(
                    "-f mpegts",
                    "-i `"concat:$FileList`"",
                    "-c copy",
                    "-bsf:a aac_adtstoasc",
                    "`"$TempFolder/$CourseName/$SectionName.mp4`""
                )
                Wait = $True
                RedirectStandardError = "/dev/null"
                NoNewWindow = $True
            }
            Start-Process @ProcessArguments


            $ProcessArguments = @{
                FilePath = "$FFMPEG"
                ArgumentList = @(
                    "-i `"$TempFolder/$CourseName/$SectionName.mp4`"",
                    "-i `"$MetadataFileName`"",
                    "-map_metadata 1",
                    "-codec copy `"$OutputFolder/$CourseName/$SectionName.mp4`""
                )
                Wait = $True
                RedirectStandardError = "/dev/null"
                NoNewWindow = $True
            }
           Start-Process @ProcessArguments

        Remove-Item $TempFolder/$CourseName -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

end {


}