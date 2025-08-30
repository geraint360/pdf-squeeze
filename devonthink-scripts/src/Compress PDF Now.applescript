-- PDF Squeeze for DEVONthink 4
-- Purpose: Compress the currently selected PDFs in DEVONthink using ~/bin/pdf-squeeze
-- Put into ~/Library/Application Scripts/com.devon-technologies.think/Menu
-- Logging: ~/Library/Logs/pdf-squeeze.log

on logMsg(m)
  try
    set ts to do shell script "/bin/date '+%Y-%m-%d %H:%M:%S'"
    set logline to ts & " [Compress Now] " & m & linefeed
    do shell script "/bin/mkdir -p ~/Library/Logs; /usr/bin/printf %s " & quoted form of logline & " >> ~/Library/Logs/pdf-squeeze.log"
  end try
end logMsg

on findTool()
  set sh to "
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
        set nm to (name of r as text)
        set pth to (path of r)
        if pth is missing value then error "Record has no file path: " & nm

        set cmd to quoted form of toolPath & " --inplace --min-gain 1 " & quoted form of pth & " 2>&1"
        my logMsg("Running on: " & nm & "  (" & pth & ")")
        set out to do shell script cmd
        if out is not "" then my logMsg("Output:" & linefeed & out)
        update record r
        my logMsg("Done: " & nm)
      end if
    on error errMsg number errNum
      my logMsg("ERROR on record '" & (name of r as text) & "': " & errMsg & " (" & errNum & ")")
      display notification errMsg with title "pdf-squeeze" subtitle (name of r)
    end try
  end repeat
end tell