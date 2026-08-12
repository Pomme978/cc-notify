-- Sélectionne une session iTerm par identifiant et y saisit un texte, suivi
-- d'un retour chariot. Sert à répondre à Claude depuis la bannière.
-- Arguments : identifiant de session, texte. Le texte est facultatif : sans
-- lui, le script se contente de ramener le focus.
on run argv
	if (count of argv) is 0 then return
	set targetId to item 1 of argv
	set txt to ""
	if (count of argv) > 1 then set txt to item 2 of argv
	tell application "iTerm2"
		activate
		repeat with w in windows
			repeat with t in tabs of w
				repeat with s in sessions of t
					if (id of s) is targetId then
						select w
						select t
						select s
						if txt is not "" then
							tell s to write text txt
						end if
						return
					end if
				end repeat
			end repeat
		end repeat
	end tell
end run
