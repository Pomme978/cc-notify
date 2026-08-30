-- Active iTerm2 et sélectionne la session dont l'identifiant est passé en
-- argument. Si la session n'existe plus, iTerm est simplement activé.
on run argv
	if (count of argv) is 0 then return
	set targetId to item 1 of argv
	tell application "iTerm2"
		activate
		repeat with w in windows
			repeat with t in tabs of w
				repeat with s in sessions of t
					if (id of s) is targetId then
						select w
						select t
						select s
						return
					end if
				end repeat
			end repeat
		end repeat
	end tell
end run
