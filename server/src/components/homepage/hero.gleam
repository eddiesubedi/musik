import components/fade_img
import components/homepage/model.{type Hero, type Msg}
import gleam/int
import gleam/list
import gleam/string
import lib/img
import lustre/attribute.{attribute as attr}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg

pub fn view(hero: Hero) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "[--hero-h:737px] md:[--hero-h:560px]  lg:[--hero-h:600px]  xl:[--hero-h:713px] [--content-width:400px] opacity-0 transition-opacity duration-700",
      ),
      attribute.styles([#("--hue", int.to_string(hero.banner_hue))]),
    ],
    [
      html.div([attribute.class("h-[var(--hero-h)] relative")], [
        html.img(
          list.flatten([
            img.srcset(
              hero.banner,
              [320, 384, 448, 541, 576, 672, 768, 896, 1024, 1152, 1280, 1920],
              "",
            ),
            [
              attribute.class(
                "object-cover md:object-right-top w-full h-full absolute",
              ),
              attr("crossorigin", "anonymous"),
              attr(
                "onerror",
                "this.onerror=null;this.srcset='';this.src='https://images.unsplash.com/photo-1519638399535-1b036603ac77';var p=this.closest('[style*=\"--hue\"]');p.classList.remove('opacity-0');p.classList.add('opacity-100')",
              ),
              attr(
                "onload",
                "var p=this.closest('[style*=\"--hue\"]');var c=document.createElement('canvas'),x=c.getContext('2d');c.width=100;c.height=100;x.drawImage(this,0,0,100,100);var d=x.getImageData(0,0,100,100).data,rt=0,gt=0,bt=0,at=0;for(var i=0;i<d.length;i+=4){var a=d[i+3];rt+=d[i]*d[i]*a;gt+=d[i+1]*d[i+1]*a;bt+=d[i+2]*d[i+2]*a;at+=a}var R=at?Math.sqrt(rt/at)/255:0,G=at?Math.sqrt(gt/at)/255:0,B=at?Math.sqrt(bt/at)/255:0,mn=Math.min(R,G,B),mx=Math.max(R,G,B),hu=0;if(mx!==mn){var df=mx-mn;hu=mx===R?((G-B)/df+(G<B?6:0))*60:mx===G?((B-R)/df+2)*60:((R-G)/df+4)*60}p.style.setProperty('--hue',Math.round(hu));p.classList.remove('opacity-0');p.classList.add('opacity-100')",
              ),
            ],
          ]),
        ),
        html.div(
          [
            attribute.class(
              "md:hidden absolute w-full h-full bg-gradient-to-b from-transparent via-transparent via-5% to-black to-95%",
            ),
          ],
          [],
        ),
        //mobile gradiant
        generate_mobile_gradiants(),
        generate_desktop_gradiants(),
        html.div(
          [
            attribute.class(
              "absolute py-16 px-[12.083333333333334vw] md:px-[7.8125vw] lg:px-[6.0546875vw] xl:px-[5.208333333333334vw] w-full h-full flex items-end",
            ),
          ],
          [
            html.div([attribute.class("max-w-[var(--content-width)]")], [
              logo(hero),
              html.p(
                [
                  attribute.class(
                    " leading-tight lg:leading-normal hidden md:line-clamp-3 mt-2 lg:text-lg ",
                  ),
                  attribute.title(hero.description),
                ],
                [
                  html.text(hero.description),
                ],
              ),
              html.p(
                [
                  attribute.class(
                    " mt-2 font-light text-sm lg:text-base lg:font-normal",
                  ),
                ],
                [
                  html.text(
                    string.concat([
                      hero.score,
                      " • ",
                      string.join(list.take(hero.genres, 3), with: ", "),
                      " • ",
                      hero.year,
                    ]),
                  ),
                ],
              ),
              html.div(
                [
                  attribute.class(
                    "tracking-widest text-sm font-semibold flex items-center mt-6",
                  ),
                ],
                [
                  html.button(
                    [
                      attribute.class(
                        "bg-white text-black flex items-center gap-2 px-6 h-12 rounded cursor-pointer hover:opacity-75 transition-opacity mr-6",
                      ),
                    ],
                    [
                      html.svg(
                        [
                          attr("width", "10"),
                          attr("height", "12"),
                          attr("viewBox", "0 0 10 12"),
                        ],
                        [
                          svg.g([], [
                            svg.path([
                              attr(
                                "d",
                                "M9.3 6.5L1 11.6C0.7 11.7 0.4 11.6 0.3 11.4 0.2 11.3 0.2 11.2 0.2 11.1L0 0.9C0 0.6 0.2 0.4
                    0.5 0.4 0.6 0.4 0.7 0.4 0.8 0.5L9.3 5.7C9.5 5.8 9.6 6.1 9.5 6.4 9.4 6.4 9.4 6.5 9.3 6.5Z",
                              ),
                            ]),
                          ]),
                        ],
                      ),
                      html.span([attribute.class("uppercase")], [
                        html.text("Play"),
                      ]),
                    ],
                  ),
                  html.button(
                    [
                      attribute.class(
                        "bg-transparent  flex items-center gap-2 px-6 h-12 rounded border-2 border-white cursor-pointer
                        hover:opacity-75 transition-opacity mr-2",
                      ),
                    ],
                    [
                      html.span([attribute.class("uppercase")], [
                        html.text("Details"),
                      ]),
                    ],
                  ),
                  html.svg(
                    [
                      attribute.class(
                        " cursor-pointer hover:opacity-75 transition-opacity",
                      ),
                      attr("viewBox", "0 0 24 24"),
                      attr("width", "24"),
                      attr("height", "24"),
                      attr("stroke", "currentColor"),
                      attr("stroke-width", "2"),
                      attr("stroke-linecap", "round"),
                      attr("stroke-linejoin", "round"),
                      attr("aria-hidden", "true"),
                      attr("focusable", "false"),
                    ],
                    [
                      svg.circle([
                        attr("cx", "12"),
                        attr("cy", "12"),
                        attr("r", "1"),
                      ]),
                      svg.circle([
                        attr("cx", "12"),
                        attr("cy", "5"),
                        attr("r", "1"),
                      ]),
                      svg.circle([
                        attr("cx", "12"),
                        attr("cy", "19"),
                        attr("r", "1"),
                      ]),
                    ],
                  ),
                ],
              ),
            ]),
          ],
        ),
      ]),
    ],
  )
}

fn logo(hero: Hero) -> Element(Msg) {
  case hero.logo {
    "" ->
      html.h1(
        [
          attribute.class(" text-5xl font-bold max-w-[var(--content-width)]"),
        ],
        [
          html.text(hero.name),
        ],
      )
    _ ->
      fade_img.view("max-w-[var(--content-width)] max-h-[155px]", [
        attribute.src(img.url(hero.logo, "trim:10/")),
        attr(
          "onerror",
          "this.onerror=null;this.outerHTML='<h1 class=\" text-5xl font-bold max-w-[var(--content-width)] line-clamp-2 leading-tight\">"
            <> hero.name
            <> "</h1>'",
        ),
      ])
  }
}

fn generate_mobile_gradiants() -> Element(Msg) {
  html.div([attribute.class("md:hidden")], [
    html.div(
      [
        attribute.class(
          "w-full h-[calc(var(--hero-h)*.15)] top-[calc(var(--hero-h)*.85)] bg-black absolute",
        ),
      ],
      [],
    ),
    html.div(
      [
        attribute.class(
          "w-full h-[calc(var(--hero-h)*.85)] bg-[linear-gradient(1turn,#000,transparent_59.36%)] absolute",
        ),
      ],
      [],
    ),
    html.div(
      [
        attribute.class(
          "w-full h-full absolute bg-[linear-gradient(25.8deg,hsla(var(--hue),100%,60%,.75)_0,hsla(var(--hue),100%,60%,0)_39.03%)]",
        ),
      ],
      [],
    ),
    html.div(
      [
        attribute.class(
          "w-full h-full absolute bg-[linear-gradient(150.24deg,hsla(var(--hue),50%,40%,.5)_0,hsla(var(--hue),50%,40%,0)_98.9%)]",
        ),
      ],
      [],
    ),
  ])
}

fn generate_desktop_gradiants() -> Element(Msg) {
  html.div([attribute.class("hidden md:block")], [
    html.div(
      [
        attribute.class(
          "w-full h-full bg-[linear-gradient(48.6deg,rgba(0,0,0,.8)_16.43%,transparent_82.35%)] absolute",
        ),
      ],
      [],
    ),
    html.div(
      [
        attribute.class(
          "w-full h-full absolute bg-[linear-gradient(81.74deg,#000_6.34%,transparent_55.87%)]",
        ),
      ],
      [],
    ),
    html.div(
      [
        attribute.class(
          "w-full h-full absolute bg-[linear-gradient(135.65deg,hsla(var(--hue),50%,40%,.45)_0,hsla(var(--hue),50%,40%,0)_28.89%)]",
        ),
      ],
      [],
    ),
    html.div(
      [
        attribute.class(
          "w-full h-full absolute bg-[linear-gradient(124.86deg,hsla(var(--hue),100%,60%,.65)_0,hsla(var(--hue),100%,60%,0)_58.22%)]",
        ),
      ],
      [],
    ),
    html.div(
      [
        attribute.class(
          "w-full h-full absolute bg-[linear-gradient(180deg,#16181d,rgba(22,24,29,0)_50%)] [transform:matrix(1,0,0,-1,0,0)]",
        ),
      ],
      [],
    ),
  ])
}
