; UJR - Universal Joystick Remapper

#SingleInstance Off

; Create an instance of the library
ADHD := New ADHDLib

; Ensure running as admin
ADHD.run_as_admin()

; ============================================================================================
; CONFIG SECTION - Configure ADHD

; Authors - Edit this section to configure ADHD according to your macro.
; You should not add extra things here (except add more records to hotkey_list etc)
; Also you should generally not delete things here - set them to a different value instead

; You may need to edit these depending on game
SendMode, Event
SetKeyDelay, 0, 50

; Stuff for the About box

ADHD.config_about({name: "UJR", version: 5.0, author: "evilC", link: "<a href=""http://evilc.com/proj/ujr"">Homepage</a>"})
; The default application to limit hotkeys to.
; Starts disabled by default, so no danger setting to whatever you want
;ADHD.config_default_app("CryENGINE")

; GUI size
ADHD.config_size(600,500)

; Defines your hotkeys 
; subroutine is the label (subroutine name - like MySub: ) to be called on press of bound key
; uiname is what to refer to it as in the UI (ie Human readable, with spaces)
ADHD.config_hotkey_add({uiname: "Fire", subroutine: "Fire"})

; Hook into ADHD events
; First parameter is name of event to hook into, second parameter is a function name to launch on that event
ADHD.config_event("option_changed", "option_changed_hook")
ADHD.config_event("program_mode_on", "program_mode_on_hook")
ADHD.config_event("program_mode_off", "program_mode_off_hook")
ADHD.config_event("app_active", "app_active_hook")
ADHD.config_event("app_inactive", "app_inactive_hook")
ADHD.config_event("disable_timers", "disable_timers_hook")
ADHD.config_event("resolution_changed", "resolution_changed_hook")

; Add custom tabs
ADHD.tab_list := Array("Axes", "Buttons 1", "Buttons 2", "Hats")

; Init ADHD
ADHD.init()
ADHD.create_gui()

; Init the PPJoy / vJoy library
#include VJoyLib\VJoy_lib.ahk

LoadPackagedLibrary() {
    if (A_PtrSize < 8) {
        dllpath = VJoyLib\x86\vJoyInterface.dll
    } else {
        dllpath = VJoyLib\x64\vJoyInterface.dll
    }
    hDLL := DLLCall("LoadLibrary", "Str", dllpath)
    if (!hDLL) {
        MsgBox, [%A_ThisFunc%] LoadLibrary %dllpath% fail
    }
    return hDLL
} 

LoadPackagedLibrary()
vjoy_id := 1
VJoy_Init(vjoy_id)

; Init stick vars for AHK
axis_list_ahk := Array("X","Y","Z","R","U","V")

; Init stick vars for vJoy
axis_list_vjoy := Array("X","Y","Z","RX","RY","RZ","SL0","SL1")
manual_control := 0
virtual_axes := 8
virtual_buttons := VJoy_GetVJDButtonNumber(vjoy_id)
;virtual_hats := VJoy_GetContPovNumber(vjoy_id)
virtual_hats := 1	; AHK currently can only read one hat per stick

; Mapping array - A multidimensional array holding Axis mappings
; The first element is the mapping for the first virtual axis, the second element for axis 2, etc, etc
; Each element is then comprise of a further array:
; [Physical Joystick #,Physical Axis #, Scale (-1 = invert)]
axis_mapping := Array()
button_mapping := Array()
hat_mapping := Array()

; When axes are to be merged - the first axis to be processed stores it's value in this array
; The second axis can then use the value in here to merge with the first axis
merged_axes := Array()

; The "Axes" tab is tab 1
Gui, Tab, 1


; ============================================================================================
; GUI SECTION

gui_width := 600
w:=gui_width-10

th1 := 45
th2 := th1+5

; AXES TAB
; --------
Gui, Add, Text, x20 y%th1% w30 R2 Center, Virtual Axis
Gui, Add, Text, x70 y%th1% w50 R2 Center, Axis Merging
Gui, Add, Text, x125 y%th1% w60 R2 Center, Physical Stick ID
Gui, Add, Text, x185 y%th1% w60 R2 Center, Physical Axis
Gui, Add, Text, x240 y%th2% w100 h20 Center, State
Gui, Add, Text, x335 y%th2% w40 h20 Center, Invert
Gui, Add, Text, x380 y%th2% w50 R2 Center, % "Deadzone %"
Gui, Add, Text, x435 y%th2% w50 R2 Center, % "Sensitivity %"
Gui, Add, Text, x485 y%th2% w50 h20 Center, Physical
Gui, Add, Text, x540 y%th2% w50 h20 Center, Virtual

Loop, %virtual_axes% {
	ypos := 70 + A_Index * 30
	ypos2 := ypos + 5
	ADHD.gui_add("DropDownList", "virtual_axis_id_" A_Index, "x10 y" ypos " w50 h20 R9", "None|1|2|3|4|5|6|7|8", "None")
	ADHD.gui_add("DropDownList", "virtual_axis_merge_" A_Index, "x70 y" ypos " w50 h20 R9", "None||On", "None")
	ADHD.gui_add("DropDownList", "axis_physical_stick_id_" A_Index, "x130 y" ypos " w50 h20 R9", "None|1|2|3|4|5|6|7|8", "None")
	ADHD.gui_add("DropDownList", "physical_axis_id_" A_Index, "x190 y" ypos " w50 h20 R9", "None|1|2|3|4|5|6|7|8", "None")
	Gui, Add, Slider, x240 y%ypos% w100 h20 vaxis_state_slider_%A_Index%
	ADHD.gui_add("CheckBox", "virtual_axis_invert_" A_Index, "x345 y" ypos " w20 h20", "", 0)
	ADHD.gui_add("Edit", "virtual_axis_deadzone_" A_Index, "x385 y" ypos " w40 h21", "", 0)
	ADHD.gui_add("Edit", "virtual_axis_sensitivity_" A_Index, "x440 y" ypos " w40 h21", "", 0)
	Gui, Add, Text, x490 y%ypos% w40 h21 Center vphysical_value_%A_Index%, 0
	Gui, Add, Text, x540 y%ypos% w40 h21 Center vvirtual_value_%A_Index%, 0
}

; End GUI creation section
; ============================================================================================

ADHD.finish_startup()

; =============================================================================================================================
; MAIN LOOP - controls the virtual stick
Loop{
	; Clear axes - for axis merging, we need each axis to start at -1 so we know if we have altered it yet
	Loop, %virtual_axes% {
		merged_axes[%A_Index%] := -1
	}
	
	; Cycle through rows. MAY NOT BE IN ORDER OF VIRTUAL AXES!
	For index, value in axis_mapping {
		;if (virtual_axis_id_%index% != "None" && axis_mapping[index].id != "None" && axis_mapping[index].axis != "None"){
		if (virtual_axis_id_%index% != "None"){
			; Main section for active axes
			if (!manual_control){	; Normal mode
				; Get input value
				val := GetKeyState(value.id . "Joy" . axis_list_ahk[value.axis])

				; Display input value, rescale to -100 to +100
				GuiControl,, physical_value_%index%, % round((val-50)*2,2)
				
				; Adjust axis according to invert / deadzone options etc
				val := AdjustAxis(val,value)
				
				; Display output value, rescale to -100 to +100
				GuiControl,, virtual_value_%index%, % round((val-50)*2,2)
				; Move slider to show input value
				GuiControl,, axis_state_slider_%index%, % val
			} else {	; manual control mode
				GuiControlGet, val,, axis_state_slider_%index%
				val := AdjustAxis(val,value)
			}
			
			; Set the value for this axis on the virtual stick
			axismap := axis_list_vjoy[value.virt_axis]

			ax := value.axis
			if (value.merge != "None"){
				if (merged_axes[%ax%] == -1){
					merged_axes[%ax%] := val
				} else {
					val := ((val/2)+50) + ((merged_axes[%ax%]/2) * -1)
				}
			}
			; rescale to vJoy style 0->32767
			val := val * 327.67
			VJoy_SetAxis(val, vjoy_id, HID_USAGE_%axismap%)

		} else {
			; Blank out unused axes
			GuiControl,, physical_value_%index%, 
			GuiControl,, virtual_value_%index%, 
			GuiControl,, axis_state_slider_%index%, 50
		}
		
	}
	
	/*
	For index, value in button_mapping {
		if (button_mapping[index].id != "None" && button_mapping[index].button != "None"){
			if (manual_control == 0){
				if (value.pov){
					; get current state of pov in val
					val := PovToAngle(GetKeyState(value.id . "Joy" . "POV"))
					; Does it match the current mapping?
					val := PovMatchesAngle(val,value.pov)
					SetButtonState(index,val)
				} else {
					val := GetKeyState(value.id . "Joy" . value.button)
					SetButtonState(index,val)
				}
			} else {
				GuiControlGet, val,, button_state_%index%
				if (val == "On"){
					val := 1
				} else {
					val := 0
				}
			}
			VJoy_SetBtn(val, vjoy_id, index)
		}		
	}
	
	For index, value in hat_mapping {
		if (hat_mapping[index].id != "None"){
			if (manual_control == 0){
				VJoy_SetContPov(GetKeyState(value.id . "Joy" . "POV"), vjoy_id, A_Index)
			}
		}
	}
	*/
	Sleep, 10
}
return

; ============================================================================================
; FUNCTIONS

; Make adjustments to axis based upon settings
AdjustAxis(input,settings){
	; Shift from 0 -> 100 scale to -50 -> +50 scale
	output := input - 50
	
	; invert if needed
	output := output * settings.invert
	
	; impose deadzone if set
	dz := settings.deadzone
	
	if (abs(output) <= settings.deadzone/2){
		output := 0
	} else {
		output := sign(output)*50*(abs(output)-(settings.deadzone/2))/(50-settings.deadzone/2)
	}
	
	; Adjust for sensitivity
	if (settings.sensitivity != 100){
		sens := settings.sensitivity/100 ; Shift sensitivity to 0 -> 1 scale
		output := output/50	; Shift input value to -1 -> +1 scale
		output := (sens*output)+((1-sens)*output**3)	; Perform sensitivity calc
		output := output*50	; Shift back to -50 -> 50 scale

	}
	
	; Shift back to proper scale
	output := output + 50
	
	return output
}

; Detects the sign (+ or -) of a number and returns a multiplier for that sign
sign(input){
	if (input < 0){
		return -1
	} else {
		return 1
	}
}


; ============================================================================================
; EVENT HOOKS

; This is fired when settings change (including on load). Use it to pre-calculate values etc.
option_changed_hook(){
	Global virtual_axes
	Global axis_mapping
	
	Loop, %virtual_axes% {
		axis_mapping[A_Index] := Object()
		
		axis_mapping[A_Index].virt_axis := virtual_axis_id_%A_Index%

		axis_mapping[A_Index].merge := virtual_axis_merge_%A_Index%

		axis_mapping[A_Index].id := axis_physical_stick_id_%A_Index%

		axis_mapping[A_Index].axis := physical_axis_id_%A_Index%
		
		if(virtual_axis_invert_%A_Index% == 0){
			axis_mapping[A_Index].invert := 1
		} else {
			axis_mapping[A_Index].invert := -1
		}
		
		if virtual_axis_deadzone_%A_Index% is not number
			GuiControl,,virtual_axis_deadzone_%A_Index%,0
		else
			axis_mapping[A_Index].deadzone := virtual_axis_deadzone_%A_Index%
		
		
		if virtual_axis_sensitivity_%A_Index% is not number
			GuiControl,,virtual_axis_sensitivity_%A_Index%,100
		else
			axis_mapping[A_Index].sensitivity := virtual_axis_sensitivity_%A_Index%
	}
	
	return
}

; ============================================================================================
; ACTIONS


; Macro is trying to fire - timer label
Fire:
	return

; ===================================================================================================
; FOOTER SECTION

; KEEP THIS AT THE END!!
;#Include ADHDLib.ahk		; If you have the library in the same folder as your macro, use this
#Include <ADHDLib>			; If you have the library in the Lib folder (C:\Program Files\Autohotkey\Lib), use this
