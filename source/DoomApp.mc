import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class DoomApp extends Application.AppBase {

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var view = new DoomView();
        return [view, new DoomDelegate()];
    }
}
