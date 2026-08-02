use base64::engine::general_purpose;
use base64::Engine as _;
use image::Luma;
use qrcode::QrCode;

pub fn png_base64(payload: &str) -> Result<String, String> {
    let code = QrCode::new(payload.as_bytes()).map_err(|e| e.to_string())?;
    let image = code
        .render::<Luma<u8>>()
        .min_dimensions(240, 240)
        .max_dimensions(480, 480)
        .build();
    let mut bytes: Vec<u8> = Vec::new();
    let mut cursor = std::io::Cursor::new(&mut bytes);
    image
        .write_to(&mut cursor, image::ImageFormat::Png)
        .map_err(|e| e.to_string())?;
    Ok(general_purpose::STANDARD.encode(bytes))
}
