import gleam/list
import lib/img
import lustre/attribute.{type Attribute, attribute as attr}
import lustre/element.{type Element}
import lustre/element/html

/// An image that fades in when loaded. Pass a class string and any extra attributes.
pub fn view(class: String, attrs: List(Attribute(a))) -> Element(a) {
  html.img(
    list.flatten([
      [
        attribute.class("opacity-0 transition-opacity duration-700 " <> class),
        attr(
          "onload",
          "this.classList.remove('opacity-0');this.classList.add('opacity-100')",
        ),
      ],
      attrs,
    ]),
  )
}

/// A responsive fade-in image with srcset. Pass widths, imgproxy options, a class string, and any extra attributes.
pub fn responsive(
  source: String,
  widths: List(Int),
  options: String,
  class: String,
  attrs: List(Attribute(a)),
) -> Element(a) {
  html.img(
    list.flatten([
      [
        attribute.class("opacity-0 transition-opacity duration-700 " <> class),
        attr(
          "onload",
          "this.classList.remove('opacity-0');this.classList.add('opacity-100')",
        ),
      ],
      img.srcset(source, widths, options),
      attrs,
    ]),
  )
}
