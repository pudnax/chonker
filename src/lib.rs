use std::path::PathBuf;

mod frame_counter;
mod input;
mod shader_compiler;
mod state;
mod utils;
mod watcher;

use color_eyre::eyre::Result;
use frame_counter::FrameCounter;
use input::Input;
use pollster::FutureExt;
use winit::{
    dpi::PhysicalSize,
    event::{ElementState, Event, KeyboardInput, VirtualKeyCode, WindowEvent},
    event_loop::{ControlFlow, EventLoop},
    window::Window,
};

const SHADER_FOLDER: &str = "shaders";

pub async fn run(
    event_loop: EventLoop<(PathBuf, wgpu::ShaderModule)>,
    window: Window,
) -> Result<()> {
    let mut state = state::State::new(&window, &event_loop).block_on()?;

    let mut frame_counter = FrameCounter::new();
    let mut input = Input::new();

    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::Wait;

        match event {
            Event::MainEventsCleared => {
                state.update(&frame_counter, &input);
                window.request_redraw();
            }
            Event::WindowEvent { event, .. } => {
                input.update(&event, &window);
                match event {
                    WindowEvent::CloseRequested
                    | WindowEvent::KeyboardInput {
                        input:
                            KeyboardInput {
                                virtual_keycode: Some(VirtualKeyCode::Escape),
                                state: ElementState::Pressed,
                                ..
                            },
                        ..
                    } => *control_flow = ControlFlow::Exit,

                    WindowEvent::Resized(PhysicalSize { width, height })
                    | WindowEvent::ScaleFactorChanged {
                        new_inner_size: &mut PhysicalSize { width, height },
                        ..
                    } => {
                        if width != 0 && height != 0 {
                            state.resize(width, height);
                        }
                    }

                    _ => {}
                }
            }
            Event::RedrawRequested(_) => {
                frame_counter.record();
                match state.render() {
                    Ok(_) => {}
                    Err(wgpu::SurfaceError::Lost) => {
                        state.resize(state.width, state.height);
                        window.request_redraw();
                    }
                    Err(wgpu::SurfaceError::OutOfMemory) => *control_flow = ControlFlow::Exit,
                    Err(e) => {
                        eprintln!("{:?}", e);
                        window.request_redraw();
                    }
                }
            }
            Event::UserEvent((path, shader)) => state.register_shader_change(path, shader),
            _ => {}
        }
    })
}
