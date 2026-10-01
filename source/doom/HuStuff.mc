// hu_stuff.c / hu_stuff.h
//
// DESCRIPTION:  Heads-up displays
//
// Only the message line is here: no chat, no automap title, and the
// text is drawn with a watch font instead of the STCFN patches (the
// hu_lib text widgets come down to one string).

import Toybox.Graphics;
import Toybox.Lang;

(:extendedCode)
module HuStuff {

    const HU_MSGTIMEOUT = 4 * DoomDef.TICRATE;

    // m_menu.c: show messages has default, 0 = off, 1 = on
    var showMessages as Number = 1;

    var plr as Number = 0;
    var message_on as Boolean = false;
    var message_dontfuckwithme as Boolean = false;
    var message_nottobefuckedwith as Boolean = false;
    var message_counter as Number = 0;

    var headsupactive as Boolean = false;

    // w_message: the one line HU_MSGHEIGHT is set to
    var w_message as String = "";

    function HU_Stop() as Void {
        headsupactive = false;
    }

    function HU_Start() as Void {
        if (headsupactive) {
            HU_Stop();
        }

        plr = DPlayer.consoleplayer;
        message_on = false;
        message_dontfuckwithme = false;
        message_nottobefuckedwith = false;

        // create the message widget
        w_message = "";

        headsupactive = true;
    }

    // Draws the message centered at x, y (screen pixels). The C version
    // draws at HU_MSGX, HU_MSGY into the frame buffer.
    function HU_Drawer(dc as Graphics.Dc, x as Number, y as Number) as Void {
        // HUlib_drawSText(&w_message);
        if (message_on) {
            dc.setColor(Graphics.COLOR_RED, Graphics.COLOR_TRANSPARENT);
            dc.drawText(x, y, Graphics.FONT_XTINY, w_message, Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function HU_Ticker() as Void {
        // tick down message counter if message is up
        if (message_counter != 0) {
            message_counter--;
            if (message_counter == 0) {
                message_on = false;
                message_nottobefuckedwith = false;
            }
        }

        if (showMessages != 0 || message_dontfuckwithme) {
            // display message if necessary
            var message = DPlayer.players_message[plr];
            if ((message != null && !message_nottobefuckedwith)
                || (message != null && message_dontfuckwithme)) {
                // HUlib_addMessageToSText(&w_message, 0, plr->message);
                w_message = message;
                DPlayer.players_message[plr] = null;
                message_on = true;
                message_counter = HU_MSGTIMEOUT;
                message_nottobefuckedwith = message_dontfuckwithme;
                message_dontfuckwithme = false;
            }
        } // else message_on = false;

        // (no netgame chat)
    }
}
