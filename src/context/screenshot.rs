use std::num::NonZeroU32;

use crate::utils::ImageDimentions;
use wgpu::{Device, MapMode};

pub struct ScreenshotCtx {
    pub image_dimentions: ImageDimentions,
    data: wgpu::Buffer,
}

impl ScreenshotCtx {
    pub fn resize(&mut self, device: &Device, width: u32, height: u32) {
        // puffin::profile_function!();
        let new_dims = ImageDimentions::new(width, height, wgpu::COPY_BYTES_PER_ROW_ALIGNMENT);
        if new_dims.linear_size() > self.image_dimentions.linear_size() {
            // puffin::profile_scope!("Reallocating Buffer");
            let image_dimentions =
                ImageDimentions::new(width, height, wgpu::COPY_BYTES_PER_ROW_ALIGNMENT);

            self.data = create_host_buffer(device, &image_dimentions);
        }
        self.image_dimentions = new_dims;
    }

    pub fn new(device: &Device, width: u32, height: u32) -> Self {
        let image_dimentions =
            ImageDimentions::new(width, height, wgpu::COPY_BYTES_PER_ROW_ALIGNMENT);

        let data = create_host_buffer(device, &image_dimentions);

        Self {
            image_dimentions,
            data,
        }
    }

    pub fn capture_frame(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        src_texture: &wgpu::Texture,
    ) -> (Vec<u8>, ImageDimentions) {
        // puffin::profile_function!();
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("Capture Encoder"),
        });
        let copy_size = wgpu::Extent3d {
            width: self.image_dimentions.width,
            height: self.image_dimentions.height,
            depth_or_array_layers: 1,
        };
        encoder.copy_texture_to_buffer(
            src_texture.as_image_copy(),
            wgpu::ImageCopyBuffer {
                buffer: &self.data,
                layout: wgpu::ImageDataLayout {
                    offset: 0,
                    bytes_per_row: Some(
                        NonZeroU32::new(self.image_dimentions.padded_bytes_per_row).unwrap(),
                    ),
                    rows_per_image: Some(NonZeroU32::new(self.image_dimentions.height).unwrap()),
                },
            },
            copy_size,
        );

        queue.submit(Some(encoder.finish()));

        let image_slice = self.data.slice(0..self.image_dimentions.linear_size());
        let _ = image_slice.map_async(MapMode::Read);

        device.poll(wgpu::Maintain::Wait);
        let frame = image_slice.get_mapped_range().to_vec();
        self.data.unmap();

        (frame, self.image_dimentions)
    }
}

fn create_host_buffer(device: &wgpu::Device, image_dimentions: &ImageDimentions) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("Screenshot Buffer"),
        size: image_dimentions.linear_size(),
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}
