module dsubs_client.world.manager;

import std.experimental.logger;
import std.algorithm;
import std.range;

import dsubs_common.math.transform;

import dsubs_client.core.component;
import dsubs_client.input.router;
import dsubs_client.render.render;


/// Manages world-space objects rendering and IO event handling (selection)
class WorldManager: ComponentManager!"world", IWindowDrawer, IWindowEventHandler
{
    /// Transform of the camera.
    Transform2D camera;
}
