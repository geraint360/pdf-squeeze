-- PDF Squeeze for DEVONthink 4
-- Purpose: Smart Rule handler to compress matched PDFs via ~/bin/pdf-squeeze
-- Put into ~/Library/Application Scripts/com.devon-technologies.think/Smart Rules
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

-- Smart Rule - PDF Squeeze.scpt (DEVONthink 4)
-- Attach this to your Smart Rule with “Execute Script”
property logFile : (POSIX path of (path to library folder from user domain)) & "Logs/pdf-squeeze.log"

on writeLog(msg)
	try
		do shell script "mkdir -p " & quoted form of ((POSIX path of (path to library folder from user domain)) & "Logs/")
		do shell script "printf %s " & quoted form of (msg & linefeed) & " >> " & quoted form of logFile
	end try
end writeLog

on performSmartRule(theRecords)
	set tool to my pathToPdfSqueeze()
	repeat with r in theRecords
		try
			tell application id "DNtp"
				set thePath to (path of r as string)
			end tell
			set p to POSIX path of thePath
			set cmd to quoted form of tool & " --inplace --min-gain 1 " & quoted form of p
			my writeLog("SmartRule: " & cmd)
			do shell script cmd
			my writeLog("SmartRule OK: " & p)
		on error errMsg number errNum
			my writeLog("SmartRule ERROR(" & errNum & "): " & errMsg)
		end try
	end repeat
end performSmartRule

-- same helper:
on pathToPdfSqueeze()
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