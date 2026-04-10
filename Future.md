I am writing a native IOS version of my frontend.
The old project is in ./frontend, the new project is in ./ios.

Create a new script "run-ios" that runs the simulator and builds the app in ios. If i run it again it should re-build and update the simulator. I will be running xcode commands from within this dev shell and I'm aware nix overwrites the linker among other things, take a look at the old run-ios script from a few commits ago that I have since deleted, this was a script that worked with the ./frontend react-native build.

I am rewriting my reat-native project in Swift.
The old project is in ./frontend, the new project is in ./ios.
Do not copy any styling. Use default styling for SwiftUI including icons etc.
Use strict TDD, always write unit tests first. No UI tests.
I will run tests manually for validation, do not run any xcode commands - notify if you need me to run any.

Implement the auth flow for the settings page. It needs to support annon accounts just like the react-native-project.

# NEXT

Add the price 

Also ensure that this pill scroll correctly conveys the case where there is overflow.
