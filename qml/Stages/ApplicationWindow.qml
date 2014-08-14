/*
 * Copyright 2014 Canonical Ltd.
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; version 3.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program. If not, see <http://www.gnu.org/licenses/>.
 */

import QtQuick 2.0
import Ubuntu.Components 1.1
import Unity.Application 0.1

Item {
    id: root

    // to be read from outside
    readonly property bool fullscreen: application ? application.fullscreen : false

    // to be set from outside
    property bool interactive: true
    property QtObject application

    QtObject {
        id: d

        // helpers so that we don't have to check for the existence of an application everywhere
        // (in order to avoid breaking qml binding due to a javascript exception)
        readonly property string name: root.application ? root.application.name : ""
        readonly property url icon: root.application ? root.application.icon : ""
        readonly property Item surface: root.application ? root.application.surface : null
        readonly property int applicationState: root.application ? root.application.state : -1
        readonly property var promptSurfaces: root.application ? root.application.promptSurfaces : null

        property bool needToTakeScreenshot:
            d.surface && d.surfaceInitialized && screenshotImage.status === Image.Null
            && d.applicationState === ApplicationInfo.Stopped
        onNeedToTakeScreenshotChanged: {
            if (needToTakeScreenshot) {
                screenshotImage.take();
            }
        }

        //FIXME - this is a hack to avoid the first few rendered frames as they
        // might show the UI accommodating due to surface resizes on startup.
        // Remove this when possible
        property bool surfaceInitialized: false
        onSurfaceChanged: {
            if (surface) {
                surfaceInitTimer.start();
            } else {
                surfaceInitialized = false;
            }
        }
    }

    Timer {
        id: surfaceInitTimer
        interval: 100
        onTriggered: { if (d.surface) {d.surfaceInitialized = true;} }
    }

    SurfaceContainer {
        id: surfaceContainer
        objectName: "surfaceContainer"
        anchors.fill: parent
        surface: d.surface

        Binding {
            target: surface
            property: "enabled"
            value: root.interactive
        }
        Binding {
            target: surface
            property: "focus"
            value: root.interactive
        }

        Connections {
            target: surface
            // FIXME: I would rather not need to do this, but currently it doesn't get
            // active focus without it and I don't know why.
            onFocusChanged: forceSurfaceActiveFocusIfReady();
            onParentChanged: forceSurfaceActiveFocusIfReady();
            onEnabledChanged: forceSurfaceActiveFocusIfReady();
            function forceSurfaceActiveFocusIfReady() {
                if (surface.focus && surface.parent === surfaceContainer && surface.enabled) {
                    surface.forceActiveFocus();
                }
            }
        }
    }

    Image {
        id: screenshotImage
        objectName: "screenshotImage"
        source: ""
        anchors.fill: parent

        function take() {
            // Format: "image://application/$APP_ID/$CURRENT_TIME_MS"
            // eg: "image://application/calculator-app/123456"
            var timeMs = new Date().getTime();
            source = "image://application/" + root.application.appId + "/" + timeMs;
        }

        onSourceChanged: { console.log("screenshotImage.source = " + source); }
    }

    Loader {
        id: splashLoader
        visible: active
        active: false
        anchors.fill: surfaceContainer
        sourceComponent: Component {
            Splash { name: d.name; image: d.icon }
        }
    }

    Repeater {
        model: d.promptSurfaces

        delegate: SurfaceContainer {
            anchors {
                fill: container
            }

            surface: modelData

            Component.onCompleted: {
                animateIn();
            }
        }
    }

    StateGroup {
        objectName: "applicationWindowStateGroup"
        states: [
            State {
                name: "splashScreen"
                when:
                     (!d.surface || !d.surfaceInitialized)
                     &&
                     screenshotImage.status !== Image.Ready
            },
            State {
                name: "surface"
                when:
                      (d.surface && d.surfaceInitialized)
                      &&
                      (d.applicationState !== ApplicationInfo.Stopped
                       || screenshotImage.status !== Image.Ready)
            },
            State {
                name: "screenshot"
                when:
                      screenshotImage.status === Image.Ready
                      &&
                      (
                        d.applicationState === ApplicationInfo.Stopped
                        || !d.surface || !d.surfaceInitialized
                      )
            }
        ]

        // For testing purposes
        property bool transitioning: defaultToSplash.running
            || splashToSurface.running
            || surfaceToSplash.running
            || surfaceToScreenshot.running
            || screenshotToSurface.running

        transitions: [
            Transition {
                id: defaultToSplash
                from: ""; to: "splashScreen"
                PropertyAction { target: splashLoader; property: "active"; value: true }
            },
            Transition {
                id: splashToSurface
                from: "splashScreen"; to: "surface"
                SequentialAnimation {
                    PropertyAction { target: surfaceContainer
                                     property: "visible"; value: true }
                    UbuntuNumberAnimation { target: splashLoader; property: "opacity";
                                            from: 1.0; to: 0.0
                                            duration: UbuntuAnimation.BriskDuration }
                    PropertyAction { target: splashLoader; property: "active"; value: false }
                }
            },
            Transition {
                id: surfaceToSplash
                from: "surface"; to: "splashScreen"
                SequentialAnimation {
                    PropertyAction { target: splashLoader; property: "active"; value: true }
                    PropertyAction { target: surfaceContainer
                                     property: "visible"; value: true }
                    UbuntuNumberAnimation { target: splashLoader; property: "opacity";
                                            from: 0.0; to: 1.0
                                            duration: UbuntuAnimation.BriskDuration }
                }
            },
            Transition {
                id: surfaceToScreenshot
                from: "surface"; to: "screenshot"
                SequentialAnimation {
                    PropertyAction { target: screenshotImage
                                     property: "visible"; value: true }
                    UbuntuNumberAnimation { target: screenshotImage; property: "opacity";
                                            from: 0.0; to: 1.0
                                            duration: UbuntuAnimation.BriskDuration }
                    PropertyAction { target: surfaceContainer
                                     property: "visible"; value: false }
                    ScriptAction { script: { if (d.surface) { d.surface.release(); } } }
                }
            },
            Transition {
                id: screenshotToSurface
                from: "screenshot"; to: "surface"
                SequentialAnimation {
                    PropertyAction { target: surfaceContainer
                                     property: "visible"; value: true }
                    UbuntuNumberAnimation { target: screenshotImage; property: "opacity";
                                            from: 1.0; to: 0.0
                                            duration: UbuntuAnimation.BriskDuration }
                    PropertyAction { target: screenshotImage; property: "visible"; value: false }
                    PropertyAction { target: screenshotImage; property: "source"; value: "" }
                }
            }
        ]
    }

}
