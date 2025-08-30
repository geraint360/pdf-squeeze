-- PDF Squeeze for DEVONthink 4
-- Purpose: Compress the currently selected PDFs in DEVONthink using ~/bin/pdf-squeeze
-- Put into ~/Library/Application Scripts/com.devon-technologies.think/Menu
-- Logging: ~/Library/Logs/pdf-squeeze.log

property LOG_HFS : ((path to library folder from user domain) as text) & "Logs:pdf-squeeze.log"
property DEBUG_MODE : false

on logMsg(m)
	try
		set ts to do shell script "/bin/date '+%Y-%m-%d %H:%M:%S'"
		set logline to ts & " [Compress Now] " & (m as text) & linefeed
		
		-- make sure the Logs folder exists
		do shell script "/bin/mkdir -p ~/Library/Logs"
		
		-- use POSIX file (safe even if the file doesn't exist yet)
		set f to POSIX file ((POSIX path of LOG_HFS))
		
		set fh to open for access f with write permission
		try
			set eof fh to (get eof fh) -- append
		end try
		write logline to fh starting at eof
		close access fh
	on error e number n
		try
			close access f
		end try
		error e number n
	end try
end logMsg

on findTool()
	-- collect env info with a safe PATH and log it to ~/Library/Logs/pdf-squeeze.log
	set envPATH to do shell script "/bin/sh -c 'export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; printf %s \"$PATH\"'"
	set whichPdfcpu to do shell script "/bin/sh -c 'export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; command -v pdfcpu || true'"
	set whichSqueeze to do shell script "/bin/sh -c 'export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; command -v pdf-squeeze || true'"
	
	if DEBUG_MODE then
		my logMsg("DEBUG PATH=" & envPATH)
		my logMsg("DEBUG which pdfcpu=" & whichPdfcpu)
		my logMsg("DEBUG which pdf-squeeze=" & whichSqueeze)
	end if
	
	-- now resolve pdf-squeeze with the same safe PATH
	set sh to "
    export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
    if [ -x \"$HOME/bin/pdf-squeeze\" ]; then
      echo \"$HOME/bin/pdf-squeeze\";
    elif command -v pdf-squeeze >/dev/null 2>&1; then
      command -v pdf-squeeze;
    elif [ -x /opt/homebrew/bin/pdf-squeeze ]; then
      echo /opt/homebrew/bin/pdf-squeeze;
    elif [ -x /usr/local/bin/pdf-squeeze ]; then
      echo /usr/local/bin/pdf-squeeze;
    else
      echo '';
    fi"
	set p to do shell script sh
	if p is "" then error "pdf-squeeze not found. Put it in ~/bin or install via Homebrew."
	return p
end findTool

tell application id "DNtp" -- DEVONthink 4
	set sel to selection
	if sel is {} then error "Select one or more PDF records in DEVONthink."
	
	set toolPath to my findTool()
	my logMsg("Tool: " & toolPath)
	
	repeat with r in sel
		try
			if (type of r is PDF document) then
				set nm to (name of r as rich text)
				set pth to (path of r)
				if pth is missing value then error "Record has no file path: " & nm
				
				set envPATH to "export PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin; "
				set out to do shell script ("/bin/sh -c " & quoted form of (envPATH & quoted form of toolPath & " --inplace --min-gain 3 --quiet " & quoted form of pth & " 2>&1"))
				if out is not "" then my logMsg("Output:" & linefeed & out)
				
				-- Cleanup: remove any stray sibling Ò_squeezed.pdfÓ (when we kept the original)
				-- and obvious Ghostscript/temporary artifacts in the same folder.
				try
					-- remove sibling Ò*_squeezed.pdfÓ if it exists
					set rmSib to do shell script ("/bin/sh -c " & quoted form of ("p=" & quoted form of pth & "; d=$(dirname \"$p\"); b=$(basename \"$p\" .pdf); f=\"$d/${b}_squeezed.pdf\"; if [ -f \"$f\" ]; then rm -f \"$f\" && echo removed; fi"))
					if rmSib is "removed" then my logMsg("Cleanup: removed stray _squeezed.pdf")
				on error e
					my logMsg("Cleanup (sibling) error: " & e)
				end try
				
				try
					-- sweep common dot-temp patterns from Ghostscript or interrupted runs
					do shell script ("/bin/sh -c " & quoted form of ("p=" & quoted form of pth & "; d=$(dirname \"$p\"); " & Â
						"find \"$d\" -maxdepth 1 -type f \\( -name '.tmp.*' -o -name '.*.tmp.*' -o -name '*.gs.*' -o -name '*._tmp.*' -o -name '*._fin.*' \\) -delete 2>/dev/null || true"))
				on error e
					my logMsg("Cleanup (temps) error: " & e)
				end try
				
				try
					-- DT4: refresh the record from the file on disk
					tell application id "DNtp" to synchronize record r
				on error number -1701
					-- Older dictionary variants: try the classic update
					try
						tell application id "DNtp" to update record r
					end try
				end try
				my logMsg("Done: " & nm)
			end if
		on error errMsg number errNum
			my logMsg("ERROR on record '" & (name of r as rich text) & "': " & errMsg & " (" & errNum & ")")
			display notification errMsg with title "pdf-squeeze" subtitle (name of r)
		end try
	end repeat
end tell