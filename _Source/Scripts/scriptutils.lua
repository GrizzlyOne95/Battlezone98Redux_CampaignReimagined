---@meta bzscriptutils

---This is a custom light userdata representing an unique identifier for an object in the game.
---@class (exact) handle: lightuserdata

---This is a custom userdata representing an audio message handle.
---@class (exact) message: userdata

---File handle for use with ODF read functions.
---@class (exact) odfhandle: userdata

---This is a custom userdata representing a position or direction. It has three number components: x, y, and z.
---@class (exact) vector: userdata
---Negate the vector.
---@operator unm:vector
---Add two vectors.
---@operator add(vector): vector
---Subtract two vectors.
---@operator sub(vector): vector
---Multiply a number by a vector or a vector by a number.
---@operator mul(number): vector
---Multiply two vectors.
---@operator mul(vector): vector
---Divide a number by a vector or a vector by a number.
---@operator div(number): vector
---Divide two vectors.
---@operator div(vector): vector
---@field x number The X component of the vector.
---@field y number The Y component of the vector.
---@field z number The Z component of the vector.

---This is a custom userdata representing an orientation and position in space.<br>
---It has four vector components:
---- right
---- up
---- front
---- posit
---
---These share space with twelve number components:
---
---- right_x
---- right_y
---- right_z
---- up_x
---- up_y
---- up_z
---- front_x
---- front_y
---- front_z
---- posit_x
---- posit_y
---- posit_z
---@class (exact) matrix: userdata
---Multiply two matrices.
---@operator mul(matrix): matrix
---@operator mul(vector): vector
---@field right_x number The X component of the "right" direction vector.
---@field right_y number The Y component of the "right" direction vector.
---@field right_z number The Z component of the "right" direction vector.
---@field up_x number The X component of the "up" direction vector.
---@field up_y number The Y component of the "up" direction vector.
---@field up_z number The Z component of the "up" direction vector.
---@field front_x number The X component of the "front" direction vector.
---@field front_y number The Y component of the "front" direction vector.
---@field front_z number The Z component of the "front" direction vector.
---@field posit_x number The X coordinate of the position vector (posit).
---@field posit_y number The Y coordinate of the position vector (posit).
---@field posit_z number The Z coordinate of the position vector (posit).

---Defines a team number, team numbers range from 0 to 15.
---@alias teamnum 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15

---Defines a weapon mask value.
---@alias weaponmask 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 | 25 | 26 | 27 | 28 | 29 | 30 | 31

---Defines a weapon slot.
---@alias weaponslot 0 | 1 | 2 | 3 | 4

---Defines a command priority.
---@alias priority
---| 0 # Commandable
---| 1 # Uncommandable

---Globals
---[[The Lua scripting system defines some global variables that can be of use to user scripts.]]

---@type string
---Contains current build version (e.g. "1.5.2.27u1").<br>
---Battlezone 1.5 versions start with "1" and Battlezone 98 Redux versions start with "2".
GameVersion = nil

---@type number
---**[2.0+]** Contains the index of the current language.
---1. English
---2. French
---3. German
---4. Spanish
---5. Italian
---6. Portuguese
---7. Russian
Language = nil

---@type string
---**[2.0+]** Contains the full name of the current language in all-caps:<br>
---- "ENGLISH"
---- "FRENCH"
---- "GERMAN"
---- "SPANISH"
---- "ITALIAN"
---- "PORTUGUESE"
---- "RUSSIAN"
LanguageName = nil

---@type string
---**[2.0+]** Contains the two-letter language code of the current language:
---- "en"
---- "fr"
---- "de"
---- "es"
---- "it"
---- "pt"
---- "ru"
LanguageSuffix = nil

---@type string
---Contains the most recently pressed game key (e.g. "Ctrl+Z").
LastGameKey = nil

---Script Event Handlers
--[[The Lua scripting system calls these script-defined functions when various script events occur. LuaMission looks up the functions by name so they can have different functions assigned to them at runtime.]]

---Called when loading state from a save game file, allowing the script to restore its state.
---
---Data values returned from Save will be passed as parameters to Load in the same order they were returned. Load supports nil, boolean, handle, integer, number, string, vector, and matrix data types. It does not support function, thread, or arbitrary userdata types.
---
---The console window will print the loaded values in human-readable format.
---@param ... boolean|handle|integer|number|string|vector|matrix|nil
function Load(...) end

---Called when saving state to a save game file, allowing the script to preserve its state.
---
---Any values returned by this function will be passed as parameters to Load when loading the save game file. Save supports nil, boolean, handle, integer, number, string, vector, and matrix data types. It does not support function, thread, or arbitrary userdata types.
---
---The console window will print the saved values in human-readable format.
---@return boolean|handle|integer|number|string|vector|matrix|nil ...
function Save() end

---Called when the mission starts for the first time.
---
---Use this function to perform any one-time script initialization.
function Start() end

---Called any time a game key is pressed.
---
---Key is a string that consisting of zero or more modifiers (<kbd>Ctrl</kbd>, <kbd>Shift</kbd>, <kbd>Alt</kbd>) and a base key.
---
---The base key for keys corresponding to a printable ASCII character is the upper-case version of that character.
---
---The base key for other keys is the label on the keycap (e.g. <kbd>PageUp</kbd>, <kbd>PageDown</kbd>, <kbd>Home</kbd>, <kbd>End</kbd>, <kbd>Backspace</kbd>, and so forth).
---@param key string
function GameKey(key) end

---Called once per frame after updating the network system and before simulating game objects.
---
---This function performs most of the mission script's game logic.
---@param timestep number
function Update(timestep) end

---Called after any game object is created.
---
---Handle is the game object that was created.
---
---This function will get a lot of traffic so it should not do too much work.
---@param h handle
function CreateObject(h) end

---Called when a game object gets added to the mission
---
---Handle is the game object that was added
---
---This function is normally called for "important" game objects, and excludes things like Scrap pieces.
---@param h handle
function AddObject(h) end

---Called before a game object is deleted.
---
---Handle is the game object to be deleted.
---
---This function will get a lot of traffic so it should not do too much work.
---@param h handle
function DeleteObject(h) end

---Called when a player joins the session.
---
---Players that join before the host launches trigger CreatePlayer just before the first Update.
---
---Players that join joining after the host launches trigger CreatePlayer on entering the pre-game lobby.
---
---This function gets called for the local player.
---@param id integer
---@param name string
---@param team teamnum
function CreatePlayer(id, name, team) end

---Called when a player starts sending state updates.
---
---This indicates that a player has finished loaded and started simulating.
---
---This function is not called for the local player.
---@param id integer
---@param name string
---@param team teamnum
function AddPlayer(id, name, team) end

---Called when a player leaves the session.
---@param id integer
---@param name string
---@param team teamnum
function DeletePlayer(id, name, team) end

---Called when a script-defined message arrives.
---
---This function should return true if it handled the message and false, nil, or none if it did not.
---
---From is the network player id of the sender.
---
---Type is an arbitrary one-character string indicating the script-defined message type.
---
---Data values passed as parameters to Send will arrive as parameters to Receive in the same order they were sent. Receive supports nil, boolean, handle, integer, number, string, vector, and matrix data types. It does not support function, thread, or arbitrary userdata types.
---@param from integer
---@param type string
---@param ... boolean|handle|integer|number|string|vector|matrix|nil
---@return boolean
function Receive(from, type, ...) end

---Called for any in-game chat command that was not handled by the system, allowing script-defined commands.
---
---This function should return true if it handled the command and false, nil, or none if it did not.
---
---LuaMission breaks the command into:
---
---- Command is the string immediately following the '/'. For example, the command for "/foo" is "foo".
---
---- Arguments arrive as a string parameter to Command. For example "/foo 1 2 3" would receive "1 2 3".
---
---The Lua string library provides several functions that can split the string into separate items.
---
---You can use string.match with captures if you have a specific argument list:
---
---``` lua
---local foo, bar, baz = string.match(arguments, "(%g+) (%g+) (%g+)")
---```
---
---You can use string.gmatch, which returns an iterator, if you want to loop through arguments:
---
---``` lua
---for arg in string.gmatch(arguments, "%g+") do ... end
---```
---
---Check the [Lua patterns tutorial](http://lua-users.org/wiki/PatternsTutorial) and [patterns manual](http://www.lua.org/manual/5.2/manual.html#6.4.1) for more details.
---@param command string
---@param arguments string
---@return boolean
function Command(command, arguments) end

---Audio Messages
--[[These functions control audio messages, 2D sounds typically used for radio messages, voiceovers, and narration.

Audio messages use the Voice Volume setting from the Audio Options menu.]]

---Repeat the last audio message.
function RepeatAudioMessage() end

---Plays the given audio file, which must be an uncompressed RIFF WAVE (.WAV) file.
---
---Returns an audio message handle.
---@param filename string
---@return message
function AudioMessage(filename) end

---Returns true if the audio message has stopped. Returns false otherwise.
---@param msg message
---@return boolean
function IsAudioMessageDone(msg) end

---Stops the given audio message.
---@param msg message
function StopAudioMessage(msg) end

---Returns true if any audio message is playing. Returns false otherwise.
---@return boolean
function IsAudioMessagePlaying() end

---Sound Effects
--[[These functions control sound effects, either positional 3D sounds attached
to objects or global 2D sounds.

Sound effects use the Effects Volume setting from the Audio Options menu.]]

---Plays the given audio file, which must be an uncompressed RIFF WAVE (.WAV) file.
---
---Specifying an object handle creates a positional 3D sound that follows the object as it moves and stops automatically when the object goes away. Otherwise, the sound plays as a global 2D sound.
---
---Priority ranges from 0 to 100, with higher priorities taking precedence over lower priorities when there are not enough channels. The default priority is 50 if not specified.
---
---Looping sounds will play forever until explicitly stopped with StopSound or the object to which it is attached goes away. Non-looping sounds will play once and stop. The default is non-looping if not specified.
---
---Volume ranges from 0 to 100, with 0 being silent and 100 being maximum volume. The default volume is 100 if not specified.
---
---Rate overrides the playback rate of the sound file, so a value of 22050 would cause a sound file recorded at 11025 Hz to play back twice as fast. The rate defaults to the file's native rate if not specified.
---@param filename string
---@param h handle?
---@param priority integer?
---@param loop boolean?
---@param volume integer?
---@param rate integer?
function StartSound(filename, h, priority, loop, volume, rate) end

---Stops the sound using the given filename and associated with the given object. Use a handle of none or nil to stop a global 2D sound.
---@param filename string
---@param h handle?
function StopSound(filename, h) end

---Game Object
--[[These functions create, manipulate, and query game objects (vehicles, buildings, people, powerups, and scrap) and return or take as a parameter a game object handle.

Object handles are always safe to use, even if the game object itself is missing or destroyed.]]

---Returns the handle of the game object with the given label. Returns nil if none exists.
---@param label string
---@return handle
function GetHandle(label) end

---Creates a game object with the given odf name and team number at the location of a game object.
---
---Returns the handle of the created object if it created one. Returns nil if it failed.
---@param odfname string
---@param teamnum teamnum
---@param h handle
---@return handle
function BuildObject(odfname, teamnum, h) end

---Creates a game object with the given odf name and team number at a point on the named path. It uses the start of the path if no point is given.
---
---Returns the handle of the created object if it created one. Returns nil if it failed.
---@param odfname string
---@param teamnum teamnum
---@param path string
---@param point integer?
---@return handle
function BuildObject(odfname, teamnum, path, point) end

---Creates a game object with the given odf name and team number at the given position vector.
---
---Returns the handle of the created object if it created one. Returns nil if it failed.
---@param odfname string
---@param teamnum teamnum
---@param position vector
---@return handle
function BuildObject(odfname, teamnum, position) end

---Creates a game object with the given odf name and team number with the given transform matrix.
---
---Returns the handle of the created object if it created one. Returns nil if it failed.
---@param odfname string
---@param teamnum teamnum
---@param transform matrix
---@return handle
function BuildObject(odfname, teamnum, transform) end

---Removes the game object with the given handle.
---@param h handle
function RemoveObject(h) end

---Returns true if the game object's odf name matches the given odf name. Returns false otherwise.
---@param h handle
---@param odfname string
---@return boolean
function IsOdf(h, odfname) end

---Returns the odf name of the game object. Returns nil if none exists.
---@param h handle
---@return string
function GetOdf(h) end

---Returns the base config of the game object which determines what VDF/SDF model it uses. Returns nil if none exists.
---@param h handle
---@return string
function GetBase(h) end

---Returns the label of the game object (e.g. "avtank0_wingman"). Returns nil if none exists.
---@param h handle
---@return string
function GetLabel(h) end

---Set the label of the game object (e.g. `"tank1"`).
---
---ℹ️ **Note:** this function was misspelled as `SettLabel` in 1.5. It can be renamed compatibly with a short snippet of code at the top of the mission script:
---
---```lua
---SetLabel = SetLabel or SettLabel
---```
---@param h handle
---@param label string
function SetLabel(h, label) end

---Returns the four-character class signature of the game object (e.g. "WING"). Returns nil if none exists.
---@param h handle
---@return string
function GetClassSig(h) end

---Returns the class label of the game object (e.g. "wingman"). Returns nil if none exists.
---@param h handle
---@return string
function GetClassLabel(h) end

---Returns the numeric class identifier of the game object. Returns nil if none exists.
---
---Looking up the class id number in the ClassId table will convert it to a string. Looking up the class id string in the ClassId table will convert it back to a number.
---@param h handle
---@return ClassId
function GetClassId(h) end

---This is a global table that converts between class identifier numbers and class identifier names.<br>
---
---For example, `ClassId.SCRAP` or `ClassId["SCRAP"]` returns the class identifier number (7) for the Scrap class; `ClassId[7]` returns the class identifier name (`"SCRAP"`) for class identifier number 7.<br>
---
---For maintainability, always use this table instead of raw class identifier numbers.
---@enum ClassId
ClassId = {
    NONE = 0,
    HELICOPTER = 1,
    STRUCTURE1 = 2,
    POWERUP = 3,
    PERSON = 4,
    SIGN = 5,
    VEHICLE = 6,
    SCRAP = 7,
    BRIDGE = 8,
    FLOOR = 9,
    STRUCTURE2 = 10,
    SCROUNGE = 11,
    SPINNER = 12,
    HEADLIGHT_MASK = 13,
    EYEPOINT = 14,
    COM = 15,
    WEAPON = 16,
    ORDNANCE = 17,
    EXPLOSION = 18,
    CHUNK = 19,
    SORT_OBJECT = 20,
    NONCOLLIDABLE = 21,
    VEHICLE_GEOMETRY = 22,
    STRUCTURE_GEOMETRY = 23,
    WEAPON_GEOMETRY = 24,
    ORDNANCE_GEOMETRY = 25,
    TURRET_GEOMETRY = 26,
    ROTOR_GEOMETRY = 27,
    NACELLE_GEOMETRY = 28,
    FIN_GEOMETRY = 29,
    COCKPIT_GEOMETRY = 30,
    WEAPON_HARDPOINT = 31,
    CANNON_HARDPOINT = 32,
    ROCKET_HARDPOINT = 33,
    MORTAR_HARDPOINT = 34,
    SPECIAL_HARDPOINT = 35,
    FLAME_EMITTER = 36,
    SMOKE_EMITTER = 37,
    DUST_EMITTER = 38,
    PARKING_LOT = 39
}

---Returns the one-letter nation code of the game object (e.g. "a" for American, "b" for Black Dog, "c" for Chinese, and "s" for Soviet).
---
---The nation code is usually but not always the same as the first letter of the odf name. The ODF file can override the nation in the `[GameObjectClass]` section, and `player.odf` is a hard-coded exception that uses "a" instead of "p".
---@param h handle
---@return string
function GetNation(h) end

---Returns true if the game object exists. Returns false otherwise.
---@param h handle
---@return boolean
function IsValid(h) end

---Returns true if the game object exists and (if the object is a vehicle) controlled. Returns false otherwise.
---@param h handle
---@return boolean
function IsAlive(h) end

---Returns true if the game object exists and (if the object is a vehicle) controlled and piloted. Returns false otherwise.
---@param h handle
---@return boolean
function IsAliveAndPilot(h) end

---Returns true if the game object exists and is a vehicle. Returns false otherwise.
---@param h handle
---@return boolean
function IsCraft(h) end

---Returns true if the game object exists and is a building. Returns false otherwise.
---@param h handle
---@return boolean
function IsBuilding(h) end

---Returns true if the game object exists and is a person. Returns false otherwise.
---@param h handle
---@return boolean
function IsPerson(h) end

---Returns true if the game object exists and has less health than the threshold. Returns false otherwise.
---@param h handle
---@param threshold number?
---@return boolean
function IsDamaged(h, threshold) end

---**[2.1+]** Returns true if the game object was recycled by a Construction Rig on the given team.
---@param h handle
---@param team teamnum
---@return boolean
function IsRecycledByTeam(h, team) end

---Team Number
--[[These functions get and set team number. Team 0 is the neutral or environment team.]]

---Returns the game object's team number.
---@param h handle
---@return teamnum
function GetTeamNum(h) end

---Sets the game object's team number.
---@param h handle
---@param team teamnum
function SetTeamNum(h, team) end

---Returns the game object's perceived team number (as opposed to its real team number).
---
---The perceived team will differ from the real team when a player enters an empty enemy vehicle without being seen until they attack something.
---@param h handle
---@return teamnum
function GetPerceivedTeam(h) end

---Set the game object's perceived team number (as opposed to its real team number).
---
---Units on the game object's perceived team will treat it as friendly until it "blows its cover" by attacking, at which point it will revert to its real team.
---
---Units on the game object's real team will treat it as friendly regardless of its perceived team.
---@param h handle
---@param t teamnum
function SetPerceivedTeam(h, t) end

---Target
--[[These function get and set a unit's target.]]

---Sets the local player's target.
---@param t handle?
function SetUserTarget(t) end

---Returns the local player's target. Returns nil if it has none.
---@return handle
function GetUserTarget() end

---Sets the game object's target.
---@param h handle
---@param t handle
function SetTarget(h, t) end

---Returns the game object's target. Returns nil if it has none.
---@param h handle
---@return handle
function GetTarget(h) end

---Owner
--[[These functions get and set owner. The default owner for a game object is the game object that created it.]]

---Sets the game object's owner.
---@param h handle
---@param o handle
function SetOwner(h, o) end

---Returns the game object's owner. Returns nil if it has none.
---@param h handle
---@return handle
function GetOwner(h) end

---Pilot Class
--[[These functions get and set vehicle pilot class.]]

---Sets the vehicle's pilot class to the given odf name. This does nothing useful for non-vehicle game objects. An odf name of nil resets the vehicle to the default assignment based on nation.
---@param h handle
---@param odfname string
function SetPilotClass(h, odfname) end

---Returns the odf name of the vehicle's pilot class. Returns nil if none exists.
---@param h handle
---@return string
function GetPilotClass(h) end

---Position and Orientation
--[[These functions get and set position and orientation.]]

---Teleports the game object to a point on the named path. It uses the start of the path if no point is given.
---@param h handle
---@param path string
---@param point integer?
function SetPosition(h, path, point) end

---Teleports the game object to the position vector.
---@param h handle
---@param position vector
function SetPosition(h, position) end

---Teleports the game object to the position of the transform matrix.
---@param h handle
---@param transform matrix
function SetPosition(h, transform) end

---Returns the game object's position vector. Returns nil if none exists.
---@param h handle
---@return vector
function GetPosition(h) end

---Returns the path point's position vector. Returns nil if none exists.
---@param path string
---@param point integer?
---@return vector
function GetPosition(path, point) end

---Returns the game object's front vector. Returns nil if none exists.
---@param h handle
---@return vector
function GetFront(h) end

---Teleports the game object to the given transform matrix.
---@param h handle
---@param transform matrix
function SetTransform(h, transform) end

---Returns the game object's transform matrix. Returns nil if none exists.
---@param h handle
---@return matrix
function GetTransform(h) end

---Linear Velocity
--[[These functions get and set linear velocity.]]

---Returns the game object's linear velocity vector. Returns nil if none exists.
---@param h handle
---@return vector
function GetVelocity(h) end

---Sets the game object's linear velocity vector.
---@param h handle
---@param velocity vector
function SetVelocity(h, velocity) end

---Angular Velocity
--[[These functions get and set angular velocity.]]

---Returns the game object's angular velocity vector. Returns nil if none exists.
---@param h handle
---@return vector
function GetOmega(h) end

---Sets the game object's angular velocity vector.
---@param h handle
---@param omega vector
function SetOmega(h, omega) end

---Position Helpers
--[[These functions help generate position values close to a center point.]]

---Returns a ground position offset from the center by the radius in a direction controlled by the angle.
---
---If no radius is given, it uses a default radius of zero.
---
---If no angle is given, it uses a default angle of zero.
---
---An angle of zero is +X (due east), pi * 0.5 is +Z (due north), pi is -X (due west), and pi * 1.5 is -Z (due south).
---@param center vector
---@param radius number?
---@param angle number?
---@return vector
function GetCircularPos(center, radius, angle) end

---Returns a ground position in a ring around the center between minradius and maxradius with roughly the same terrain height as the terrain height at the center.
---
---This is good for scattering spawn positions around a point while excluding positions that are too high or too low.
---
---If no radius is given, it uses the default radius of zero.
---@param center vector
---@param minradius number?
---@param maxradius number?
---@return vector
function GetPositionNear(center, minradius, maxradius) end

---Shot
--[[These functions query a game object for information about ordnance hits.]]

---Returns who scored the most recent hit on the game object. Returns nil if none exists.
---@param h handle
---@return handle
function GetWhoShotMe(h) end

---Returns the last time an enemy shot the game object.
---@param h handle
---@return number
function GetLastEnemyShot(h) end

---Returns the last time a friend shot the game object.
---@param h handle
---@return number
function GetLastFriendShot(h) end

---Alliances
--[[These functions control and query alliances between teams.

The team manager assigns each player a separate team number, starting with 1 and going as high as 15. Team 0 is the neutral "environment" team.

Unless specifically overridden, every team is friendly with itself, neutral with team 0, and hostile to everyone else.]]

---Sets team alliances back to default.
function DefaultAllies() end

---Sets whether team alliances are locked. Locking alliances prevents players from allying or un-allying, preserving alliances set up by the mission script.
---@param lock boolean
function LockAllies(lock) end

---Makes the two teams allies of each other.
---
---This function affects both teams so Ally(1, 2) and Ally(2, 1) produces the identical results, unlike the "half-allied" state created by the "ally" game key.
---@param team1 teamnum
---@param team2 teamnum
function Ally(team1, team2) end

---Makes the two teams enemies of each other.
---
---This function affects both teams so UnAlly(1, 2) and UnAlly(2, 1) produces the identical results, unlike the "half-enemy" state created by the "unally" game key.
---@param team1 teamnum
---@param team2 teamnum
function UnAlly(team1, team2) end

---Returns true if team1 considers team2 an ally. Returns false otherwise.
---
---Due to the possibility of player-initiated "half-alliances", IsTeamAllied(team1, team2) might not return the same result as IsTeamAllied(team2, team1).
---@param team1 teamnum
---@param team2 teamnum
function IsTeamAllied(team1, team2) end

---Returns true if game object "me" considers game object "him" an ally. Returns false otherwise.
---
---Due to the possibility of player-initiated "half-alliances", IsAlly(me, him) might not return the same result as IsAlly(him, me).
---@param me handle
---@param him handle
---@return boolean
function IsAlly(me, him) end

---Objective Marker
--[[These functions control objective markers.

Objectives are visible to all teams from any distance and from any direction, with an arrow pointing to off-screen objectives. There is currently no way to make team-specific objectives.]]

---Sets the game object as an objective to all teams.
---@param h handle
function SetObjectiveOn(h) end

---Sets the game object back to normal.
---@param h handle
function SetObjectiveOff(h) end

---Gets the game object's visible name.
---@param h handle
---@return string
function GetObjectiveName(h) end

---Sets the game object's visible name.
---@param h handle
---@param name string
function SetObjectiveName(h, name) end

---**[2.1+]** Sets the game object's visible name. This function is effectively an alias for SetObjectiveName.
---@param h handle
---@param name string
function SetName(h, name) end

---Distance
--[[These functions measure and return the distance between a game object and a reference point.]]

---Returns the distance in meters between the two game objects.
---@param h1 handle
---@param h2 handle
---@return number
function GetDistance(h1, h2) end

---Returns the distance in meters between the game object and a point on the path. It uses the start of the path if no point is given.
---@param h1 handle
---@param path string
---@param point integer?
---@return number
function GetDistance(h1, path, point) end

---Returns the distance in meters between the game object and a position vector.
---@param h1 handle
---@param position vector
---@return number
function GetDistance(h1, position) end

---Returns the distance in meters between the game object and the position of a transform matrix.
---@param h1 handle
---@param transform matrix
---@return number
function GetDistance(h1, transform) end

---Returns true if the units are closer than the given distance of each other. Returns false otherwise.
---
---(This function is equivalent to `GetDistance (h1, h2) < d)`
---@param h1 handle
---@param h2 handle
---@param dist number
---@return boolean
function IsWithin(h1, h2, dist) end

---**[2.1+]** Returns true if the bounding spheres of the two game objects are within the specified tolerance. The default tolerance is 1.3 meters if not specified.
---@param h1 handle
---@param h2 handle
---@param tolerance number?
---@return boolean
function IsTouching(h1, h2, tolerance) end

---Nearest
--[[These functions find and return the game object of the requested type closest to a reference point.]]

---Returns the game object closest to the given game object. Returns nil if none exists.
---@param h handle
---@return handle
function GetNearestObject(h) end

---Returns the game object closest to a point on the path. It uses the start of the path if no point is given. Returns nil if none exists.
---@param path string
---@param point integer?
---@return handle
function GetNearestObject(path, point) end

---Returns the game object closest to the position vector. Returns nil if none exists.
---@param position vector
---@return handle
function GetNearestObject(position) end

---Returns the game object closest to the position of the transform matrix. Returns nil if none exists.
---@param transform matrix
---@return handle
function GetNearestObject(transform) end

---Returns the craft closest to the given game object. Returns nil if none exists.
---@param h handle
---@return handle
function GetNearestVehicle(h) end

---Returns the craft closest to a point on the path. It uses the start of the path if no point is given. Returns nil if none exists.
---@param path string
---@param point integer?
---@return handle
function GetNearestVehicle(path, point) end

---Returns the vehicle closest to the position vector. Returns nil if none exists.
---@param position vector
---@return handle
function GetNearestVehicle(position) end

---Returns the vehicle closest to the position of the transform matrix. Returns nil if none exists.
---@param transform matrix
---@return handle
function GetNearestVehicle(transform) end

---Returns the building closest to the given game object. Returns nil if none exists.
---@param h handle
---@return handle
function GetNearestBuilding(h) end

---Returns the building closest to a point on the path. It uses the start of the path if no point is given. Returns nil if none exists.
---@param path string
---@param point integer?
---@return handle
function GetNearestBuilding(path, point) end

---Returns the building closest to the position vector. Returns nil if none exists.
---@param position vector
---@return handle
function GetNearestBuilding(position) end

---Returns the building closest to the position of the transform matrix. Returns nil if none exists.
---@param transform matrix
---@return handle
function GetNearestBuilding(transform) end

---Returns the enemy closest to the given game object. Returns nil if none exists.
---@param h handle
---@return handle
function GetNearestEnemy(h) end

---Returns the enemy closest to a point on the path. It uses the start of the path if no point is given. Returns nil if none exists.
---@param path string
---@param point integer?
---@return handle
function GetNearestEnemy(path, point) end

---Returns the enemy closest to the position vector. Returns nil if none exists.
---@param position vector
---@return handle
function GetNearestEnemy(position) end

---Returns the enemy closest to the position of the transform matrix. Returns nil if none exists.
---@param transform matrix
---@return handle
function GetNearestEnemy(transform) end

---**[2.0+]** Returns the friend closest to the given game object. Returns nil if none exists.
---@param h handle
---@return handle
function GetNearestFriend(h) end

---**[2.0+]** Returns the friend closest to a point on the path. It uses the start of the path if no point is given. Returns nil if none exists.
---@param path string
---@param point integer?
---@return handle
function GetNearestFriend(path, point) end

---**[2.0+]** Returns the friend closest to the position vector. Returns nil if none exists.
---@param position vector
---@return handle
function GetNearestFriend(position) end

---**[2.0+]** Returns the friend closest to the position of the transform matrix. Returns nil if none exists.
---@param transform matrix
---@return handle
function GetNearestFriend(transform) end

---**[2.1+]** Returns the craft or person on the given team closest to the given game object. Returns nil if none exists.
---@param h handle
---@param team teamnum
---@return handle
function GetNearestUnitOnTeam(h, team) end

---**[2.1+]** Returns the craft or person on the given team closest to a point on the path. It uses the start of the path if no point is given. Returns nil if none exists.
---@param path string
---@param point integer?
---@param team teamnum
---@return handle
function GetNearestUnitOnTeam(path, point, team) end

---**[2.1+]** Returns the craft or person on the given team closest to the position of the transform matrix. Returns nil if none exists.
---@param position vector
---@param team teamnum
---@return handle
function GetNearestUnitOnTeam(position, team) end

---**[2.1+]** Returns the craft or person on the given team closest to the position vector. Returns nil if none exists.
---@param transform matrix
---@param team teamnum
---@return handle
function GetNearestUnitOnTeam(transform, team) end

---Returns how many objects with the given team and odf name are closer than the given distance.
---@param h handle
---@param dist number
---@param team teamnum
---@param odfname string
---@return integer
function CountUnitsNearObject(h, dist, team, odfname) end

---Iterators
--[[These functions return iterator functions for use with Lua's "for <variable> in <expression> do ... end" form. For example: "for h in AllCraft() do print(h, GetLabel(h)) end" will print the game object handle and label of every craft in the world.]]

---Enumerates game objects within the given distance of the game object.
---@param dist number
---@param h handle
---@return function
function ObjectsInRange(dist, h) end

---Enumerates game objects within the given distance of the path point. It uses the start of the path if no point is given.
---@param dist number
---@param path string
---@param point integer?
---@return function
function ObjectsInRange(dist, path, point) end

---Enumerates game objects within the given distance of the position vector.
---@param dist number
---@param position vector
---@return function
function ObjectsInRange(dist, position) end

---Enumerates game objects within the given distance of the transform matrix.
---@param dist number
---@param transform matrix
---@return function
function ObjectsInRange(dist, transform) end

---Enumerates all game objects.
---
---Use this function sparingly at runtime since it enumerates all game objects, including every last piece of scrap. If you're specifically looking for craft, use AllCraft() instead.
---@return function
function AllObjects() end

---Enumerates all craft.
---@return function
function AllCraft() end

---Enumerates all game objects currently selected by the local player.
---@return function
function SelectedObjects() end

---Enumerates all game objects marked as objectives.
---@return function
function ObjectiveObjects() end

---Scrap Management
--[[These functions remove scrap, either to reduce the global game object count
or to remove clutter around a location.]]

---While the global scrap count is above the limit, remove the oldest scrap piece. If no limit is given, it uses the default limit of 300.
---@param limit integer?
function GetRidOfSomeScrap(limit) end

---Clear all scrap within the given distance of a game object.
---@param distance number
---@param h handle
function ClearScrapAround(distance, h) end

---Clear all scrap within the given distance of a point on the path. It uses the start of the path if no point is given.
---@param distance number
---@param path string
---@param point integer?
function ClearScrapAround(distance, path, point) end

---Clear all scrap within the given distance of a position vector.
---@param distance number
---@param position vector
function ClearScrapAround(distance, position) end

---Clear all scrap within the given distance of the position of a transform matrix.
---@param distance number
---@param transform matrix
function ClearScrapAround(distance, transform) end

---Team Slots
--[[These functions look up game objects in team slots.]]

---This is a global table that converts between team slot numbers and team slot names.<br>
---
---For example, `TeamSlot.PLAYER` or `TeamSlot["PLAYER"]` returns the team slot (0) for the player; `TeamSlot[0]` returns the team slot name ("PLAYER") for team slot 0.<br>
---
---For maintainability, always use this table instead of raw team slot numbers.<br>
---
---Slots starting with `MIN_` and `MAX_` represent the lower and upper bound of a range of slots.
---@enum TeamSlot
TeamSlot = {
    UNDEFINED = -1,
    PLAYER = 0,
    RECYCLER = 1,
    FACTORY = 2,
    ARMORY = 3,
    CONSTRUCT = 4,
    MIN_OFFENSE = 5,
    MAX_OFFENSE = 6,
    MIN_DEFENSE = 7,
    MAX_DEFENSE = 8,
    MIN_UTILITY = 9,
    MAX_UTILITY = 10,
    MIN_BEACON = 11,
    MAX_BEACON = 12,
    MIN_POWER = 13,
    MAX_POWER = 14,
    MIN_COMM = 15,
    MAX_COMM = 16,
    MIN_REPAIR = 17,
    MAX_REPAIR = 18,
    MIN_SUPPLY = 19,
    MAX_SUPPLY = 20,
    MIN_SILO = 21,
    MAX_SILO = 22,
    MIN_BARRACKS = 23,
    MAX_BARRACKS = 24,
    MIN_GUNTOWER = 25,
    MAX_GUNTOWER = 26
}

---Get the game object in the specified team slot.
---
---It uses the local player team if no team is given.
---@param slot TeamSlot
---@param team teamnum?
---@return handle
function GetTeamSlot(slot, team) end

---Returns the game object controlled by the player on the given team. Returns nil if none exists.
---
---It uses the local player team if no team is given.
---@param team teamnum?
---@return handle
function GetPlayerHandle(team) end

---Returns the Recycler on the given team. Returns nil if none exists.
---
---It uses the local player team if no team is given.
---@param team teamnum?
---@return handle
function GetRecyclerHandle(team) end

---Returns the Factory on the given team. Returns nil if none exists.
---
---It uses the local player team if no team is given.
---@param team teamnum?
---@return handle
function GetFactoryHandle(team) end

---Returns the Armory on the given team. Returns nil if none exists.
---
---It uses the local player team if no team is given.
---@param team teamnum?
---@return handle
function GetArmoryHandle(team) end

---Returns the Constructor on the given team. Returns nil if none exists.
---
---It uses the local player team if no team is given.
---@param team teamnum?
---@return handle
function GetConstructorHandle(team) end

---Team Pilots
--[[These functions get and set pilot counts for a team.]]

---Adds pilots to the team's pilot count, clamped between zero and maximum count.
---
---Returns the new pilot count.
---@param team teamnum
---@param count integer
---@return integer
function AddPilot(team, count) end

---Sets the team's pilot count, clamped between zero and maximum count.
---
---Returns the new pilot count.
---@param team teamnum
---@param count integer
---@return integer
function SetPilot(team, count) end

---Returns the team's pilot count.
---@param team teamnum
---@return integer
function GetPilot(team) end

---Adds pilots to the team's maximum pilot count.
---
---Returns the new pilot count.
---@param team teamnum
---@param count integer
---@return integer
function AddMaxPilot(team, count) end

---Sets the team's maximum pilot count.
---
---Returns the new pilot count.
---@param team teamnum
---@param count integer
---@return integer
function SetMaxPilot(team, count) end

---Returns the team's maximum pilot count.
---@param team teamnum
---@return integer
function GetMaxPilot(team) end

---Team Scrap
--[[These functions get and set scrap values for a team.]]

---Adds to the team's scrap count, clamped between zero and maximum count.
---
---Returns the new scrap count.
---@param team teamnum
---@param count integer
---@return integer
function AddScrap(team, count) end

---Sets the team's scrap count, clamped between zero and maximum count.
---
---Returns the new scrap count.
---@param team teamnum
---@param count integer
---@return integer
function SetScrap(team, count) end

---Returns the team's scrap count.
---@param team teamnum
---@return integer
function GetScrap(team) end

---Adds to the team's maximum scrap count.
---
---Returns the new maximum scrap count.
---@param team teamnum
---@param count integer
---@return integer
function AddMaxScrap(team, count) end

---Sets the team's maximum scrap count.
---
---Returns the new maximum scrap count.
---@param team teamnum
---@param count integer
---@return integer
function SetMaxScrap(team, count) end

---Returns the team's maximum scrap count.
---@param team teamnum
---@return integer
function GetMaxScrap(team) end

---Deploy
--[[These functions control deployable craft (such as Turret Tanks or Producer units).]]

---Returns true if the game object is a deployed craft. Returns false otherwise.
---@param h handle
---@return boolean
function IsDeployed(h) end

---Tells the game object to deploy.
---@param h handle
function Deploy(h) end

---Selection
--[[These functions access selection state (i.e. whether the player has selected a game object).]]

---Returns true if the game object is selected. Returns false otherwise.
---@param h handle
---@return boolean
function IsSelected(h) end

---Mission-Critical [2.0]
--[[The "mission critical" property indicates that a game object is vital to the success of the mission and disables the "Pick Me Up" and "Recycle" commands that (eventually) cause IsAlive() to report false.]]

---**[2.0+]** Returns true if the game object is marked as mission-critical. Returns false otherwise.
---@param h handle
---@return boolean
function IsCritical(h) end

---**[2.0+]** Sets the game object's mission-critical status.
---
---If critical is true or not specified, the object is marked as mission-critical. Otherwise, the object is marked as not mission-critical.
---@param h handle
---@param critical boolean?
function SetCritical(h, critical) end

---Weapon
--[[These functions access unit weapons and damage.]]

---Sets what weapons the unit's AI process will use.
---
---To calculate the mask value, add up the values of the weapon hardpoint slots you want to enable.
---
---| Hardpoint     | Value |
---| ------------- | ----- |
---| `weaponHard1` | 1     |
---| `weaponHard2` | 2     |
---| `weaponHard3` | 4     |
---| `weaponHard4` | 8     |
---| `weaponHard5` | 16    |
---@param h handle
---@param mask weaponmask
function SetWeaponMask(h, mask) end

---Gives the game object the named weapon in the given slot. If no slot is given, it chooses a slot based on hardpoint type and weapon priority like a weapon powerup would. If the weapon name is empty, nil, or blank and a slot is given, it removes the weapon in that slot.
---
---Returns true if it succeeded. Returns false otherwise.
---@param h handle
---@param weaponname string?
---@param slot weaponslot?
---@return boolean
function GiveWeapon(h, weaponname, slot) end

---Returns the odf name of the weapon in the given slot on the game object. Returns nil if the game object does not exist or the slot is empty.
---
---For example, an "avtank" game object would return "gatstab" for index 0 and "gminigun" for index 1.
---@param h handle
---@param slot weaponslot
---@return string
function GetWeaponClass(h, slot) end

---Tells the game object to fire at the given target.
---@param me handle
---@param him handle
function FireAt(me, him) end

---Applies damage to the game object.
---@param h handle
---@param amount number
function Damage(h, amount) end

---Time
--[[These function report various global time values.]]

---Returns the elapsed time in seconds since the start of the mission.
---@return number
function GetTime() end

---Returns the simulation time step in seconds.
---@return number
function GetTimeStep() end

---Returns the current system time in milliseconds. This is mostly useful for performance profiling.
---@return number
function GetTimeNow() end

---Mission
--[[These functions control general mission properties like strategic AI and mission flow.]]

---Enables (or disables) strategic AI control for a given team. As of version 1.5.2.7, mission scripts must enable AI control for any team that intends to use an AIP.
---
---⚠️ **Important safety tip:** only call this function from the "root" of the Lua mission script! The strategic AI gets set up shortly afterward and attempting to use SetAIControl later will crash the game.
---@param team teamnum
---@param control boolean?
function SetAIControl(team, control) end

---Returns true if a given team is AI controlled. Returns false otherwise.
---
---Unlike SetAIControl, this function may be called at any time.
---@param team teamnum
---@return boolean
function GetAIControl(team) end

---Returns the current AIP for the team. It uses team 2 if no team number is given.
---@param team teamnum?
---@return string
function GetAIP(team) end

---Switches the team's AI plan. It uses team 2 if no team number is given.
---@param aipname string
---@param team teamnum?
function SetAIP(aipname, team) end

---Fails the mission after the given time elapses. If supplied with a filename (usually a .des), it sets the failure message to text from that file.
---@param time number
---@param filename string?
function FailMission(time, filename) end

---Succeeds the mission after the given time elapses. If supplied with a filename (usually a .des), it sets the success message to text from that file.
---@param time number
---@param filename string?
function SucceedMission(time, filename) end

---Objective Messages
--[[These functions control the objective panel visible at the right of the screen.]]

---Clears all objective messages.
function ClearObjectives() end

---Adds an objective message with the given name and properties.
---
---The message defaults to white if no color is given. The color may be "black", "dkgrey", "grey", "white", "blue", "dkblue", "green", "dkgreen", "yellow", "dkyellow", "red", or "dkred"; the value is case-insensitive.
---
---The message lasts 8 seconds if no duration is given.
---
---The message text defaults to the contents of the file with the specified name (usually an .otf).
---@param name string
---@param color string?
---@param duration number?
---@param text string?
function AddObjective(name, color, duration, text) end

---Updates the objective message with the given name. If no objective exists with that name, it does nothing.
---
---The message defaults to white if no color is given. The color may be "black", "dkgrey", "grey", "white", "blue", "dkblue", "green", "dkgreen", "yellow", "dkyellow", "red", or "dkred"; the value is case-insensitive.
---
---The message lasts 8 seconds if no duration is given.
---
---The message text will keep its previous value if no text is given.
---@param name string
---@param color string?
---@param duration number?
---@param text string?
function UpdateObjective(name, color, duration, text) end

---Removes the objective message with the given file name. Messages after the removed message will be moved up to fill the vacancy. If no objective exists with that file name, it does nothing.
---@param name string
function RemoveObjective(name) end

---Cockpit Timer
--[[These functions control the large timer at the top of the screen.]]

---Starts the cockpit timer counting down from the given time. If a warn time is given, the timer will turn yellow when it reaches that value. If an alert time is given, the timer will turn red when it reaches that value. All time values are in seconds.
---
---The start time can be up to 35999, which will appear on-screen as `9:59:59`. If the remaining time is an hour or less, the timer will show only minutes and seconds.
---@param time integer
---@param warn integer?
---@param alert integer?
function StartCockpitTimer(time, warn, alert) end

---Starts the cockpit timer counting up from the given time. If a warn time is given, the timer will turn yellow when it reaches that value. If an alert time is given, the timer will turn red when it reaches that value. All time values are in seconds.
---
---The on-screen timer will always show hours, minutes, and seconds. The hours digit will malfunction after 10 hours.
---@param time integer
---@param warn integer?
---@param alert integer?
function StartCockpitTimerUp(time, warn, alert) end

---Stops the cockpit timer.
function StopCockpitTimer() end

---Hides the cockpit timer.
function HideCockpitTimer() end

---Returns the current time in seconds on the cockpit timer.
---@return integer
function GetCockpitTimer() end

---Earthquake
--[[These functions control the global earthquake effect.]]

---Starts a global earthquake effect.
---@param magnitude number
function StartEarthquake(magnitude) end

---Changes the magnitude of an existing earthquake effect.
---
---⚠️ **Important:** note the inconsistent capitalization, which matches the internal C++ script utility functions.
---@param magnitude number
function UpdateEarthQuake(magnitude) end

---Stops the global earthquake effect.
function StopEarthquake() end

---Path Type
--[[These functions get and set the looping type of a path.]]

---This is a global table that converts between path type numbers and path type names.<br>
---
---Looking up the path type number in the PathType table will convert it to a string. Looking up the path type string in the PathType table will convert it to a number.
---@enum PathType
PathType = {
    ONE_WAY = 0,
    ROUND_TRIP = 1,
    LOOP = 2
}

---**[2.0+]** Changes the named path to the given path type.
---@param path string
---@param type PathType
function SetPathType(path, type) end

---**[2.0+]** Returns the type of the named path.
---@param path string
---@return PathType
function GetPathType(path) end

---Changes the named path to one-way. Once a unit reaches the end of the path, it will stop.
---@param path string
function SetPathOneWay(path) end

---Changes the named path to round-trip. Once a unit reaches the end of the path, it will follow the path backwards to the start and begin again.
---@param path string
function SetPathRoundTrip(path) end

---Changes the named path to looping. Once a unit reaches the end of the path, it will continue along to the start and begin again.
---@param path string
function SetPathLoop(path) end

---Path Points [2.0]
--[[]]

---**[2.0+]** Returns the number of points in the named path, or 0 if the path does not exist.
---@param path string
---@return integer
function GetPathPointCount(path) end

---Path Area [2.0]
--[[These functions treat a path as the boundary of a closed polygonal area.]]

---**[2.0+]** Returns how many times the named path loops around the given game object.
---
---Each full counterclockwise loop adds one and each full clockwise loop subtracts one.
---@param path string
---@param h handle
---@return integer
function GetWindingNumber(path, h) end

---**[2.0+]** Returns how many times the named path loops around the given position.
---
---Each full counterclockwise loop adds one and each full clockwise loop subtracts one.
---@param path string
---@param position vector
---@return integer
function GetWindingNumber(path, position) end

---**[2.0+]** Returns how many times the named path loops around the position of the given transform.
---
---Each full counterclockwise loop adds one and each full clockwise loop subtracts one.
---@param path string
---@param transform matrix
---@return integer
function GetWindingNumber(path, transform) end

---**[2.0+]** Returns true if the given game object is inside the area bounded by the named path. Returns false otherwise.
---
---This function is equivalent to:
---
---```lua
---GetWindingNumber( path, h ) ~= 0
---```
---@param path string
---@param h handle
---@return boolean
function IsInsideArea(path, h) end

---**[2.0+]** Returns true if the given position is inside the area bounded by the named path. Returns false otherwise.
---
---This function is equivalent to:
---
---```lua
---GetWindingNumber( path, position ) ~= 0
---```
---@param path string
---@param position vector
---@return boolean
function IsInsideArea(path, position) end

---**[2.0+]** Returns true if the position of the given transform is inside the area bounded by the named path. Returns false otherwise.
---
---This function is equivalent to:
---
---```lua
---GetWindingNumber( path, transform ) ~= 0
---```
---@param path string
---@param transform matrix
---@return boolean
function IsInsideArea(path, transform) end

---Unit Commands
--[[These functions send commands to units or query their command state.]]

---This is a global table that converts between command numbers and command names.<br>
---
---For example, `AiCommand.GO` or `AiCommand["GO"]` returns the command number (3) for the "go" command; `AiCommand[3]` returns the command name ("GO") for command number 3.<br>
---
---For maintainability, always use this table instead of raw command numbers.
---@enum AiCommand
AiCommand = {
    NONE = 0,
    SELECT = 1,
    STOP = 2,
    GO = 3,
    ATTACK = 4,
    FOLLOW = 5,
    FORMATION = 6,
    PICKUP = 7,
    DROPOFF = 8,
    NO_DROPOFF = 9,
    GET_REPAIR = 10,
    GET_RELOAD = 11,
    GET_WEAPON = 12,
    GET_CAMERA = 13,
    GET_BOMB = 14,
    DEFEND = 15,
    GO_TO_GEYSER = 16,
    RESCUE = 17,
    RECYCLE = 18,
    SCAVENGE = 19,
    HUNT = 20,
    BUILD = 21,
    PATROL = 22,
    STAGE = 23,
    SEND = 24,
    GET_IN = 25,
    LAY_MINES = 26,
    CLOAK = 27
}

---Returns true if the game object can be commanded. Returns false otherwise.
---@param me handle
---@return boolean
function CanCommand(me) end

---Returns true if the game object is a producer that can build at the moment. Returns false otherwise.
---@param me handle
---@return boolean
function CanBuild(me) end

---Returns true if the game object is a producer and currently busy. Returns false otherwise.
---@param me handle
---@return boolean
function IsBusy(me) end

---Returns the current command for the game object. Looking up the command number in the AiCommand table will convert it to a string. Looking up the command string in the AiCommand table will convert it back to a number.
---@param me handle
---@return AiCommand
function GetCurrentCommand(me) end

---Returns the target of the current command for the game object. Returns nil if it has none.
---@param me handle
---@return handle
function GetCurrentWho(me) end

---Gets the independence of a unit.
---@param me handle
---@return integer
function GetIndependence(me) end

---Sets the independence of a unit. 1 (the default) lets the unit take initiative (e.g. attack nearby enemies), while 0 prevents that.
---@param me handle
---@param independence integer
function SetIndependence(me, independence) end

---Commands the unit using the given parameters. Be careful with this since not all commands work with all units and some have strict requirements on their parameters.
---"Command" is the command to issue, normally chosen from the global AiCommand table (e.g. `AiCommand.GO`).
---
---- **Priority** is the command priority; a value of 0 leaves the unit commandable by the player while the default value of 1 makes it uncommandable.
---- **Who** is an optional target game object.
---- **Where** is an optional destination, and can be a matrix (transform), a vector (position), or a string (path name).
---- **When** is an optional absolute time value only used by command `AiCommand.STAGE`.
---- **Param** is an optional odf name only used by command `AiCommand.BUILD`.
---@param me handle
---@param command AiCommand
---@param priority priority?
---@param who handle?
---@param where matrix|vector|string?
---@param when number?
---@param param string?
function SetCommand(me, command, priority, who, where, when, param) end

---Commands the unit to attack the given target.
---@param me handle
---@param him handle
---@param priority priority?
function Attack(me, him, priority) end

---Commands the unit to go to the named path.
---@param me handle
---@param path string
---@param priority priority?
function Goto(me, path, priority) end

---Commands the unit to go to the given target.
---@param me handle
---@param him handle
---@param priority priority?
function Goto(me, him, priority) end

---Commands the unit to go to the given position vector.
---@param me handle
---@param position vector
---@param priority priority?
function Goto(me, position, priority) end

---Commands the unit to go to the position of the given transform matrix.
---@param me handle
---@param transform matrix
---@param priority priority?
function Goto(me, transform, priority) end

---Commands the unit to lay mines at the named path; only minelayer units support this.
---@param me handle
---@param path string
---@param priority priority?
function Mine(me, path, priority) end

---Commands the unit to lay mines at the given position vector.
---@param me handle
---@param position vector
---@param priority priority?
function Mine(me, position, priority) end

---Commands the unit to lay mines at the position of the transform matrix.
---@param me handle
---@param transform matrix
---@param priority priority?
function Mine(me, transform, priority) end

---Commands the unit to follow the given target.
---@param me handle
---@param him handle
---@param priority priority?
function Follow(me, him, priority) end

---**[2.1+]** Returns true if the unit is currently following the given target.
---@param me handle
---@param him handle
---@return boolean
function IsFollowing(me, him) end

---Commands the unit to defend its current location.
---@param me handle
---@param priority priority?
function Defend(me, priority) end

---Commands the unit to defend the given target.
---@param me handle
---@param him handle
---@param priority priority?
function Defend2(me, him, priority) end

---Commands the unit to stop at its current location.
---@param me handle
---@param priority priority?
function Stop(me, priority) end

---Commands the unit to patrol along the named path. This is equivalent to Goto with an independence of 1.
---@param me handle
---@param path string
---@param priority priority?
function Patrol(me, path, priority) end

---Commands the unit to retreat to the named path. This is equivalent to Goto with an independence of 0.
---@param me handle
---@param path string
---@param priority priority?
function Retreat(me, path, priority) end

---Commands the unit to retreat to the given target. This is equivalent to Goto with an independence of 0.
---@param me handle
---@param him handle
---@param priority priority?
function Retreat(me, him, priority) end

---Commands the pilot to get into the target vehicle.
---@param me handle
---@param him handle
---@param priority priority?
function GetIn(me, him, priority) end

---Commands the unit to pick up the target object. Deployed units pack up (ignoring the target), scavengers pick up scrap, and tugs pick up and carry objects.
---@param me handle
---@param him handle
---@param priority priority?
function Pickup(me, him, priority) end

---Commands the unit to drop off at the named path. Tugs drop off their cargo and Construction Rigs build the selected item at the location using their current facing.
---@param me handle
---@param path string
---@param priority priority?
function Dropoff(me, path, priority) end

---Commands the unit to drop off at the position vector. Tugs drop off their cargo and Construction Rigs build the selected item at the location using their current facing.
---@param me handle
---@param position vector
---@param priority priority?
function Dropoff(me, position, priority) end

---Commands the unit to drop off at the position of the transform matrix. Tugs drop off their cargo and Construction Rigs build the selected item with the facing of the transform matrix.
---@param me handle
---@param transform matrix
---@param priority priority?
function Dropoff(me, transform, priority) end

---Commands a producer to build the given odf name. The Armory and Construction Rig need an additional Dropoff to give them a location to build but first need at least one simulation update to process the Build.
---@param me handle
---@param odfname string
---@param priority priority?
function Build(me, odfname, priority) end

---Commands a producer to build the given odf name at the location of the target game object. A Construction Rig will build at the location and an Armory will launch the item to the location. Other producers will ignore the location.
---@param me handle
---@param odfname string
---@param target handle
---@param priority priority?
function BuildAt(me, odfname, target, priority) end

---Commands a producer to build the given odf name at the named path. A Construction Rig will build at the location and an Armory will launch the item to the location. Other producers will ignore the location.
---@param me handle
---@param odfname string
---@param path string
---@param priority priority?
function BuildAt(me, odfname, path, priority) end

---Commands a producer to build the given odf name at the position vector. A Construction Rig will build at the location with their current facing and an Armory will launch the item to the location. Other producers will ignore the location.
---@param me handle
---@param odfname string
---@param position vector
---@param priority priority?
function BuildAt(me, odfname, position, priority) end

---Commands a producer to build the given odf name at the transform matrix. A Construction Rig will build at the location with the facing of the transform and an Armory will launch the item to the location. Other producers will ignore the location.
---@param me handle
---@param odfname string
---@param transform matrix
---@param priority priority?
function BuildAt(me, odfname, transform, priority) end

---**[2.1+]** Commands the unit to follow the given target closely. This function is equivalent to `SetCommand(me, AiCommand.FORMATION, priority, him)`.
---@param me handle
---@param him handle
---@param priority priority?
function Formation(me, him, priority) end

---**[2.1+]** Commands the unit to hunt for targets autonomously. This function is equivalent to `SetCommand(me, AiCommand.HUNT, priority)`.
---@param me handle
---@param priority priority?
function Hunt(me, priority) end

---Tug Cargo
--[[These functions query Tug and Cargo.]]

---Returns true if the unit is a tug carrying cargo.
---@param tug handle
---@return boolean
function HasCargo(tug) end

---**[2.1+]** Returns the handle of the cargo if the unit is a tug carrying cargo. Returns nil otherwise.
---@param tug handle
---@return handle
function GetCargo(tug) end

---Returns the handle of the tug carrying the object. Returns nil if not carried.
---@param cargo handle
---@return handle
function GetTug(cargo) end

---Pilot Actions
--[[These functions control the pilot of a vehicle.]]

---Commands the vehicle's pilot to eject.
---@param h handle
function EjectPilot(h) end

---Commands the vehicle's pilot to hop out.
---@param h handle
function HopOut(h) end

---Kills the vehicle's pilot as if sniped.
---@param h handle
function KillPilot(h) end

---Removes the vehicle's pilot cleanly.
---@param h handle
function RemovePilot(h) end

---Returns the vehicle that the pilot most recently hopped out of.
---@param h handle
---@return handle
function HoppedOutOf(h) end

---Health Values
--[[These functions get and set health values on a game object.]]

---Returns the fractional health of the game object between 0 and 1.
---@param h handle
---@return number
function GetHealth(h) end

---Returns the current health value of the game object.
---@param h handle
---@return number
function GetCurHealth(h) end

---Returns the maximum health value of the game object.
---@param h handle
---@return number
function GetMaxHealth(h) end

---Sets the current health of the game object.
---@param h handle
---@param health number
function SetCurHealth(h, health) end

---Sets the maximum health of the game object.
---@param h handle
---@param health number
function SetMaxHealth(h, health) end

---Adds to the current health of the game object.
---@param h handle
---@param health number
function AddHealth(h, health) end

---**[2.1+]** Sets the unit's current health to maximum.
---@param h handle
function GiveMaxHealth(h) end

---Ammo Values
--[[These functions get and set ammo values on a game object.]]

---Returns the fractional ammo of the game object between 0 and 1.
---@param h handle
---@return number
function GetAmmo(h) end

---Returns the current ammo value of the game object.
---@param h handle
---@return number
function GetCurAmmo(h) end

---Returns the maximum ammo value of the game object.
---@param h handle
---@return number
function GetMaxAmmo(h) end

---Sets the current ammo of the game object.
---@param h handle
---@param ammo number
function SetCurAmmo(h, ammo) end

---Sets the maximum ammo of the game object.
---@param h handle
---@param ammo number
function SetMaxAmmo(h, ammo) end

---Adds to the current ammo of the game object.
---@param h handle
---@param ammo number
function AddAmmo(h, ammo) end

---**[2.1+]** Sets the unit's current ammo to maximum.
---@param h handle
function GiveMaxAmmo(h) end

---Cinematic Camera
--[[These functions control the cinematic camera for in-engine cut scenes (or "cineractives" as the Interstate '76 team at Activision called them).]]

---Starts the cinematic camera and disables normal input. Always returns true.
---@return boolean
function CameraReady() end

---Moves a cinematic camera along a path at a given height and speed while looking at a target game object. Returns true when the camera arrives at its destination. Returns false otherwise.
---@param path string
---@param height integer
---@param speed integer
---@param target handle
---@return boolean
function CameraPath(path, height, speed, target) end

---Moves a cinematic camera along a path at a given height and speed while looking along the path direction. Returns true when the camera arrives at its destination. Returns false otherwise.
---@param path string
---@param height integer
---@param speed integer
---@return boolean
function CameraPathDir(path, height, speed) end

---Returns true when the camera arrives at its destination. Returns false otherwise.
---@return boolean
function PanDone() end

---Offsets a cinematic camera from a base game object while looking at a target game object. The right, up, and forward offsets are in centimeters. Returns true if the base or handle game object does not exist. Returns false otherwise.
---@param base handle
---@param right integer
---@param up integer
---@param forward integer
---@param target handle
---@return boolean
function CameraObject(base, right, up, forward, target) end

---Finishes the cinematic camera and enables normal input. Always returns true.
---@return boolean
function CameraFinish() end

---Returns true if the player canceled the cinematic. Returns false otherwise.
---@return boolean
function CameraCancelled() end

---Info Display
--[[]]

---Returns true if the game object inspected by the info display matches the given odf name.
---@param odfname string
---@return boolean
function IsInfo(odfname) end

---Network
--[[LuaMission currently has limited network support, but can detect if the mission is being run in multiplayer and if the local machine is hosting.]]

---Returns true if the game is a network game. Returns false otherwise.
---@return boolean
function IsNetGame() end

---Returns true if the local machine is hosting a network game. Returns false otherwise.
---@return boolean
function IsHosting() end

---Sets the game object as local to the machine the script is running on, transferring ownership from its original owner if it was remote.
---
---⚠️ **Important safety tip:** only call this on one machine at a time!
---@param h handle
function SetLocal(h) end

---Returns true if the game object is local to the machine the script is running on. Returns false otherwise.
---@param h handle
---@return boolean
function IsLocal(h) end

---Returns true if the game object is remote to the machine the script is running on. Returns false otherwise.
---@param h handle
---@return boolean
function IsRemote(h) end

---Adds a system text message to the chat window on the local machine.
---@param message string
function DisplayMessage(message) end

---Send a script-defined message across the network.
---
---- To is the player network id of the recipient. None, nil, or 0 broadcasts to all players.
---- Type is a one-character string indicating the script-defined message type.
---- Other parameters will be sent as data and passed to the recipient's Receive function as parameters. Send supports nil, boolean, handle, integer, number, string, vector, and matrix data types. It does not support function, thread, or arbitrary userdata types.
---
---The sent packet can contain up to 244 bytes of data (255 bytes maximum for an Anet packet minus 6 bytes for the packet header and 5 bytes for the reliable transmission header).
---
---<table>
---<tr><th colspan="2">Type</th><th>Bytes</th></tr>
---<tr><td colspan="2">nil</td><td>1</td></tr>
---<tr><td colspan="2">boolean</td><td>1</td></tr>
---<tr><td rowspan="2">handle</td><td>invalid (zero)</td><td>1</td></tr>
---<tr><td>valid (nonzero)</td><td>1 + sizeof(int) = 5</td></tr>
---<tr><td rowspan="5">number</td><td>zero</td><td>1</td></tr>
---<tr><td>char (integer -128 to 127)</td><td>1 + sizeof(char) = 2</td></tr>
---<tr><td>short (integer -32768 to 32767)</td><td>1 + sizeof(short) = 3</td></tr>
---<tr><td>int (integer)</td><td>1 + sizeof(int) = 5</td></tr>
---<tr><td>double (non-integer)</td><td>1 + sizeof(double) = 9</td></tr>
---<tr><td rowspan="2">string</td><td>length &lt; 31</td><td>1 + length</td></tr>
---<tr><td>length &gt;= 31</td><td>2 + length</td></tr>
---<tr><td rowspan="2">table</td><td>count &lt; 31</td><td>1 + count + size of keys and values</td></tr>
---<tr><td>count &gt;= 31</td><td>2 + count + size of keys and values</td></tr>
---<tr><td rowspan="2">userdata</td><td>VECTOR_3D</td><td>1 + sizeof(VECTOR_3D) = 13</td></tr>
---<tr><td>MAT_3D</td><td>1 + sizeof(REDUCED_MAT) = 12</td></tr>
---</table>
---@param to integer?
---@param type string
---@param ... nil|boolean|handle|integer|number|string|vector|matrix
function Send(to, type, ...) end

---Read ODF
--[[These functions read values from an external ODF, INI, or TRN file.]]

---Opens the named file as an ODF. If the file name has no extension, the function will append ".odf" automatically.
---
---If the file is not already open, the function reads in and parses the file into an internal database. If you need to read values from it relatively frequently, save the handle into a global variable to prevent it from closing.
---
---Returns the file handle if it succeeded. Returns nil if it failed.
---@param filename string
---@return odfhandle
function OpenODF(filename) end

---Reads a boolean value from the named label in the named section of the ODF file. Use a nil section to read labels that aren't in a section.
---
---It considers values starting with 'Y', 'y', 'T', 't', or '1' to be true and value starting with 'N', 'n', 'F', 'f', or '0' to be false. Other values are considered undefined.
---
---If a value is not found or is undefined, it uses the default value. If no default value is given, the default value is false.
---
---Returns the value and whether the value was found.
---@param odf odfhandle
---@param section string?
---@param label string
---@param default boolean?
---@return boolean
---@return boolean
function GetODFBool(odf, section, label, default) end

---Reads an integer value from the named label in the named section of the ODF file. Use nil as the section to read labels that aren't in a section.
---
---If no value is found, it uses the default value. If no default value is given, the default value is 0.
---
---Returns the value and whether the value was found.
---@param odf odfhandle
---@param section string?
---@param label string
---@param default integer?
---@return integer
---@return boolean
function GetODFInt(odf, section, label, default) end

---Reads a floating-point value from the named label in the named section of the ODF file. Use nil as the section to read labels that aren't in a section.
---
---If no value is found, it uses the default value. If no default value is given, the default value is 0.0.
---
---Returns the value and whether the value was found.
---@param odf odfhandle
---@param section string?
---@param label string
---@param default number?
---@return number
---@return boolean
function GetODFFloat(odf, section, label, default) end

---Reads a string value from the named label in the named section of the ODF file. Use nil as the section to read labels that aren't in a section.
---
---If a value is not found, it uses the default value. If no default value is given, the default value is nil.
---
---Returns the value and whether the value was found.
---@param odf odfhandle
---@param section string?
---@param label string
---@param default string?
---@return string
---@return boolean
function GetODFString(odf, section, label, default) end

---Terrain
--[[These functions return height and normal from the terrain height field.]]

---Returns the terrain height and normal vector at the location of the game object.
---@param h handle
---@return number
---@return vector
function GetTerrainHeightAndNormal(h) end

---Returns the terrain height and normal vector at a point on the named path. It uses the start of the path if no point is given.
---@param path string?
---@param point integer
---@return number
---@return vector
function GetTerrainHeightAndNormal(path, point) end

---Returns the terrain height and normal vector at the position vector.
---@param position vector
---@return number
---@return vector
function GetTerrainHeightAndNormal(position) end

---Returns the terrain height and normal vector at the position of the transform matrix.
---@param transform matrix
---@return number
---@return vector
function GetTerrainHeightAndNormal(transform) end

---Floor
--[[These functions return height and normal from the terrain height field and the upward-facing polygons of any entities marked as floor owners.]]

---Returns the floor height and normal vector at the location of the game object.
---@param h handle
---@return number
---@return vector
function GetFloorHeightAndNormal(h) end

---Returns the floor height and normal vector at a point on the named path. It uses the start of the path if no point is given.
---@param path string?
---@param point integer
---@return number
---@return vector
function GetFloorHeightAndNormal(path, point) end

---Returns the floor height and normal vector at the position vector.
---@param position vector
---@return number
---@return vector
function GetFloorHeightAndNormal(position) end

---Returns the floor height and normal vector at the position of the transform matrix.
---@param transform matrix
---@return number
---@return vector
function GetFloorHeightAndNormal(transform) end

---Map
--[[]]

---**[2.0+]** Returns the name of the BZN file for the map. This can be used to generate an ODF name for mission settings.
---@return string
function GetMissionFilename() end

---Returns the name of the TRN file for the map. This can be used with OpenODF() to read values from the TRN file.
---@return string
function GetMapTRNFilename() end

---Files [2.0]
--[[]]

---**[2.0+]** Returns the contents of the named file as a string, or nil if the file could not be opened.
---@param filename string
---@return string
function UseItem(filename) end

---Effects [2.0]
--[[]]

---**[2.0+]** Starts a full screen color fade.
---
---Ratio sets the opacity, with 0.0 transparent and 1.0 almost opaque
---
---Rate sets how fast the opacity decreases over time.
---
---R, G, and B set the color components and range from 0 to 255
---@param ratio number
---@param rate number
---@param r integer
---@param g integer
---@param b integer
function ColorFade(ratio, rate, r, g, b) end

---Vector
--[[This is a custom userdata representing a position or direction. It has three number components: x, y, and z.]]

---Returns a vector whose components have the given number values. If no value is given for a component, the default value is 0.0.
---@param x number?
---@param y number?
---@param z number?
---@return vector
function SetVector(x, y, z) end

---Returns the [dot product](http://en.wikipedia.org/wiki/Dot_product) between vectors a and b.
---
---Equivalent to `a.x * b.x + a.y * b.y + a.z * b.z`.
---@param a vector
---@param b vector
---@return number
function DotProduct(a, b) end

---Returns the [cross product](http://en.wikipedia.org/wiki/Cross_product) between vectors a and b.
---
---Equivalent to `SetVector(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)`.
---@param a vector
---@param b vector
---@return vector
function CrossProduct(a, b) end

---Returns the vector scaled to unit length.
---
---Equivalent to `SetVector(v.x * scale, v.y * scale, v.z * scale)` where scale is `1.0f / sqrt(v.x^2 + v.y^2 + v.z^2)`.
---@param v vector
---@return vector
function Normalize(v) end

---Returns the length of the vector.
---
---Equivalent to `sqrt(v.x^2 + v.y^2 + v.z^2)`.
---@param v vector
---@return number
function Length(v) end

---Returns the squared length of the vector.
---
---Equivalent to `v.x^2 + v.y^2 + v.z^2`.
---@param v vector
---@return number
function LengthSquared(v) end

---Returns the 2D distance between vectors a and b.
---
---Equivalent to `sqrt((b.x - a.x)^2 + (b.z - a.z)^2)`.
---@param a vector
---@param b vector
---@return number
function Distance2D(a, b) end

---Returns the squared 2D distance of the vector.
---
---Equivalent to `(b.x - a.x)^2 + (b.z - a.z)^2`.
---@param a vector
---@param b vector
---@return number
function Distance2DSquared(a, b) end

---Returns the 3D distance between vectors a and b.
---
---Equivalent to `sqrt((b.x - a.x)^2 + (b.y - a.y)^2 + (b.z - a.z)^2)`.
---@param a vector
---@param b vector
---@return number
function Distance3D(a, b) end

---Returns the squared 3D distance of the vector.
---
---Equivalent to `(b.x - a.x)^2 + (b.y - a.y)^2 + (b.z - a.z)^2`.
---@param a vector
---@param b vector
---@return number
function Distance3DSquared(a, b) end

---Matrix
--[[This is a custom userdata representing an orientation and position in space. It has four vector components (right, up, front, and posit) sharing space with twelve number components (right_x, right_y, right_z, up_x, up_y, up_z, front_x, front_y, front_z, posit_x, posit_y, posit_z).]]

---Returns a matrix whose components have the given number values. If no value is given for a component, the default value is zero. Be careful with this since it's easy to build a non-orthonormal matrix that will break all kinds of built-in assumptions.
---@param right_x number?
---@param right_y number?
---@param right_z number?
---@param up_x number?
---@param up_y number?
---@param up_z number?
---@param front_x number?
---@param front_y number?
---@param front_z number?
---@param posit_x number?
---@param posit_y number?
---@param posit_z number?
---@return matrix
function SetMatrix(right_x, right_y, right_z, up_x, up_y, up_z, front_x, front_y, front_z, posit_x, posit_y, posit_z) end

---@type matrix
---Global value representing the identity matrix.<br>
---Equivalent to SetMatrix(1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0).
IdentityMatrix = nil

---Build a matrix representing a rotation by an angle around an axis. The angle is in radians. If no value is given for the angle or an axis component, the default value is zero. The axis must be unit-length (i.e. axis_x^2 + axis_y^2 + axis_z^2 = 1.0 or the resulting matrix will be wrong.
---@param angle number?
---@param axis_x number?
---@param axis_y number?
---@param axis_z number?
---@return matrix
function BuildAxisRotationMatrix(angle, axis_x, axis_y, axis_z) end

---Build a matrix representing a rotation by an angle around an axis. The angle is in radians. If no value is given for the angle, the default value is zero. The axis must be unit-length (i.e. axis.x^2 + axis.y^2 + axis.z^2 = 1.0 or the resulting matrix will be wrong.
---@param angle number?
---@param axis vector
---@return matrix
function BuildAxisRotationMatrix(angle, axis) end

---Build a matrix with the given pitch, yaw, and roll angles and position. The angles are in radians. If no value is given for a component, the default value is zero.
---@param pitch number?
---@param yaw number?
---@param roll number?
---@param posit_x number?
---@param posit_y number?
---@param posit_z number?
---@return matrix
function BuildPositionRotationMatrix(pitch, yaw, roll, posit_x, posit_y, posit_z) end

---Build a matrix with the given pitch, yaw, and roll angles and position. The angles are in radians. If no value is given for a component, the default value is zero.
---@param pitch number?
---@param yaw number?
---@param roll number?
---@param position vector
---@return matrix
function BuildPositionRotationMatrix(pitch, yaw, roll, position) end

---Build a matrix with zero position, its up axis along the specified up vector, oriented so that its front axis points as close as possible to the heading vector. If up is not specified, the default value is the Y axis. If heading is not specified, the default value is the Z axis.
---@param up vector?
---@param heading vector?
---@return matrix
function BuildOrthogonalMatrix(up, heading) end

---Build a matrix with the given position vector, its front axis pointing along the direction vector, and zero roll. If position is not specified, the default value is a zero vector. If direction is not specified, the default value is the Z axis.
---@param position vector?
---@param direction vector?
---@return matrix
function BuildDirectionalMatrix(position, direction) end

---Portal Functions [2.1]
--[[These functions control the Portal building introduced in The Red Odyssey expansion.]]

---**[2.1+]** Sets the specified Portal direction to "out", indicated by a blue visual effect while active.
---@param portal handle
function PortalOut(portal) end

---**[2.1+]** Sets the specified Portal direction to "in", indicated by an orange visual effect while active.
---@param portal handle
function PortalIn(portal) end

---**[2.1+]** Deactivates the specified Portal, stopping the visual effect.
---@param portal handle
function DeactivatePortal(portal) end

---**[2.1+]** Activates the specified Portal, starting the visual effect.
---@param portal handle
function ActivatePortal(portal) end

---**[2.1+]** Returns true if the specified Portal direction is "in". Returns false otherwise.
---@param portal handle
---@return boolean
function IsIn(portal) end

---**[2.1+]** Returns true if the specified Portal is active. Returns false otherwise.
---
---⚠️ **Important:** note the capitalization!
---@param portal handle
---@return boolean
function isPortalActive(portal) end

---**[2.1+]** Creates a game object with the given odf name and team number at the location of a portal.
---
---The object is created at the location of the visual effect and given a 50 m/s initial velocity.
---@param odfname string
---@param teamnum teamnum
---@param portal handle
---@return handle
function BuildObjectAtPortal(odfname, teamnum, portal) end

---Cloak [2.1]
--[[These functions control the cloaking state of craft capable of cloaking.]]

---**[2.1+]** Makes the specified unit cloak if it can.
---
---ℹ️ **Note:** unlike `SetCommand(h, AiCommand.CLOAK)`, this does not change the unit's current command.
---@param h handle
function Cloak(h) end

---**[2.1+]** Makes the specified unit de-cloak if it can.
---
---ℹ️ **Note:** unlike `SetCommand(h, AiCommand.DECLOAK)`, this does not change the unit's current command.
---@param h handle
function Decloak(h) end

---**[2.1+]** Instantly sets the unit as cloaked (with no fade out).
---@param h handle
function SetCloaked(h) end

---**[2.1+]** Instant sets the unit as uncloaked (with no fade in).
---@param h handle
function SetDecloaked(h) end

---**[2.1+]** Returns true if the unit is cloaked. Returns false otherwise
---@param h handle
---@return boolean
function IsCloaked(h) end

---**[2.1+]** Enable or disable cloaking for a specified cloaking-capable unit.
---
---ℹ️ **Note:** this does not grant a non-cloaking-capable unit the ability to cloak.
---@param h handle
---@param enable boolean
function EnableCloaking(h, enable) end

---Enable or disable cloaking for all cloaking-capable units.
---
---ℹ️ **Note:** this does not grant a non-cloaking-capable unit the ability to cloak.
---@param enable boolean
function EnableAllCloaking(enable) end

---Hide [2.1]
--[[These functions hide and show game objects. When hidden, the object is invisible (similar to Phantom VIR and cloak) and undetectable on radar (similar to RED Field and cloak). The effect is similar to but separate from cloaking. For the most part, AI units ignore the hidden state.]]

---**[2.1+]** Hides a game object.
---@param h handle
function Hide(h) end

---**[2.1+]** Un-hides a game object.
---@param h handle
function UnHide(h) end

---Explosion [2.1]
--[[These functions create explosions at a specified location. They do not return a handle because explosions are not game objects and thus not visible to the scripting system.]]

---**[2.1+]** Creates an explosion with the given odf name at the location of a game object.
---@param odfname string
---@param h handle
function MakeExplosion(odfname, h) end

---**[2.1+]** Creates an explosion with the given odf name at the start of the named path.
---@param odfname string
---@param path string
function MakeExplosion(odfname, path) end

---**[2.1+]** Creates an explosion with the given odf name at the given position vector.
---@param odfname string
---@param position vector
function MakeExplosion(odfname, position) end

---**[2.1+]** Creates an explosion with the given odf name with the given transform matrix.
---@param odfname string
---@param transform matrix
function MakeExplosion(odfname, transform) end
