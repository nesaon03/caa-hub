========================================================================
  COMMAND AN ARMY  --  KEY SYSTEM  (ONYX HUB / Junkie)
========================================================================

FILES
  loader.luau    the script you hand out. Runs the key check, then the hub.
  hub.luau       the hub itself. No key code inside it.

Both live in:
  C:\Users\cheating\AppData\Local\Real\workspace\CAAHub\

That folder is the executor workspace - readfile()/writefile() resolve there,
so the loader can read hub.luau with no hosting.


------------------------------------------------------------------------
  STEP 1  -  DONE
------------------------------------------------------------------------
The identifier is already set (line 25):

    identifier = "1177507",  -- Junkie dashboard user id

Verified live against api.jnkie.com - the server resolves this account,
and Junkie.get_key_link() returns:

    https://jnkie.com/flow/4c3461df-821a-4b53-a41f-ce43f6f0be18

Hand that link to your users so they can generate their own key. MOCK
mode is off now: every key is checked against the real server.

  * To go back to mock mode for testing UI, set identifier = "0".
  * The old "Invalid user ID in identifier field" error is gone - that
    was the wrong id being sent (service id / provider id are NOT it).


------------------------------------------------------------------------
  STEP 2  -  TEST
------------------------------------------------------------------------
execute loader.luau. You should see:

    [KEY] key box bound: true

A window titled KEY REQUIRED appears. Paste a key.

  valid key   ->  "[KEY] hub loaded", window closes, hub opens
  bad key     ->  Status line shows "Key not found"

Close the window without a valid key -> hub does NOT load. That is the
point of the gate.


------------------------------------------------------------------------
  HOW IT BEHAVES
------------------------------------------------------------------------
  * Saved key:  cached in CAAHub/key.txt with a 1 hour TTL. Re-running
    the script inside that hour validates silently and skips the window.
  * Auto check: starts ~0.5s after you stop typing/pasting, once the text
    is 32+ chars. No button press needed.
  * VALIDATE:   manual check, always available.
  * GET KEY:    copies your key link to the clipboard. Needs a lootlabs
    or linkvertise integration wired on the dashboard first, otherwise it
    reports that no link is available.
  * HWID_BANNED: kicks you. Fatal by design.
  * Your key is also exposed as getgenv().SCRIPT_KEY for the hub to read.


------------------------------------------------------------------------
  SHIPPING IT
------------------------------------------------------------------------
Inside the game, the loader reads the hub from the workspace file - that
only works on your own machine. To hand this to other people:

  1. upload hub.luau somewhere it can be fetched (GitHub raw, pastebin,
     your own host)
  2. in loader.luau set:
         hub_url = "https://your-host/hub.luau"
  3. hand out loader.luau only

When hub_url is set the local file is ignored, so you can push hub
updates without resending the loader. Keys stay server-side either way.


------------------------------------------------------------------------
  FIXED WHILE BUILDING
------------------------------------------------------------------------
WindUI's Input callback is not trustworthy - it reports its own internal
state and hands back an empty string even when the box visibly holds a
key, and Input.Value only refreshes through WindUI's own Set path. A
programmatic write never reaches it.

The loader binds directly to the TextBox the element owns:

    tb:GetPropertyChangedSignal("Text"):Connect(...)

and the auto-validator reads the live TextBox every tick instead of
trusting that signal alone. Both paths verified live.


------------------------------------------------------------------------
  SECURITY
------------------------------------------------------------------------
Your Junkie REST API key must NEVER go inside these scripts. It can mint
and delete keys across your whole account, and anyone who loads the file
can read it. The loader only ever calls the public check_key path.

Keep the REST key local. Rotate it if it has been shared in a chat,
screenshot, or paste.

========================================================================
