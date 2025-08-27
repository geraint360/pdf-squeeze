-- PDF Squeeze for DEVONthink 4
-- Purpose: Compress the currently selected PDFs in DEVONthink using ~/bin/pdf-squeeze
-- Put into ~/Library/Application Scripts/com.devon-technologies.think/Menu
-- Logging: ~/Library/Logs/pdf-squeeze.log

on pathToPdfSqueeze()
	-- Ordered candidates: user bin, Homebrew (arm64), Homebrew (intel), system
	set candidates to {POSIX path of (path to home folder) & "bin/pdf-squeeze", ¬
		"/opt/homebrew/bin/pdf-squeeze", "/usr/local/bin/pdf-squeeze", "/usr/bin/pdf-squeeze"}
	repeat with p in candidates
		try
			do shell script "test -x " & quoted form of p
			return p
		end try
	end repeat
	try
		set found to do shell script "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin command -v pdf-squeeze || true"
		if found is not "" then return found
	end try
	error "pdf-squeeze not found. Install it (make install-bin) or adjust your PATH."
end pathToPdfSqueeze

-- Compress PDF Now.scpt (DEVONthink 4)
property logFile : (POSIX path of (path to library folder from user domain)) & "Logs/pdf-squeeze.log"

on writeLog(msg)
	try
		do shell script "mkdir -p " & quoted form of ((POSIX path of (path to library folder from user domain)) & "Logs/")
		do shell script "printf %s " & quoted form of (msg & linefeed) & " >> " & quoted form of logFile
	end try
end writeLog

on performSmartRule(theRecords)
	my runOnRecords(theRecords)
end performSmartRule

on runOnRecords(theRecords)
	set tool to my pathToPdfSqueeze()
	repeat with r in theRecords
		try
			tell application id "DNtp"
				set thePath to (path of r as string)
			end tell
			set p to POSIX path of thePath
			set cmd to quoted form of tool & " --inplace --min-gain 1 " & quoted form of p
			my writeLog("Running: " & cmd)
			do shell script cmd
			my writeLog("OK: " & p)
		on error errMsg number errNum
			my writeLog("ERROR(" & errNum & "): " & errMsg)
		end try
	end repeat
end runOnRecords
	end tell
end run