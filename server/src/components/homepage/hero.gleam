import components/fade_img
import components/homepage/model.{
  type Hero, type Msg, ToggleMute, VideoEnded, VideoPlaying,
}
import gleam/dynamic/decode
import gleam/int
import gleam/json
import gleam/list
import gleam/string
import lib/img
import lustre/attribute.{attribute as attr}
import lustre/element.{type Element}
import lustre/element/html
import lustre/element/svg
import lustre/event

pub fn view(hero: Hero, video_playing: Bool, muted: Bool) -> Element(Msg) {
  html.div(
    [
      attribute.class(
        "[--hero-h:737px] md:[--hero-h:560px]  lg:[--hero-h:600px]  xl:[--hero-h:713px] [--content-width:400px] opacity-0 transition-opacity duration-700",
      ),
      attribute.styles([#("--hue", int.to_string(hero.banner_hue))]),
    ],
    [
      html.div(
        [
          attribute.class("h-[var(--hero-h)] relative"),
        ],
        [
          // Mobile: poster image (portrait) if available, otherwise banner
          mobile_banner(hero),
          // Desktop: landscape banner
          html.img(
            list.flatten([
              img.srcset(
                hero.banner,
                [828, 1080, 1280, 1920, 2560],
                "q:100/f:webp/",
              ),
              [
                attribute.class(
                  "hidden md:block object-cover object-right-top w-full h-full absolute",
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
          // Video: 16:9 inline on mobile, background cover on desktop
          case hero.trailer_url {
            "" -> element.none()
            url -> {
              let opacity = case video_playing {
                True -> "opacity-100"
                False -> "opacity-0"
              }
              html.div(
                [
                  attribute.class(
                    "absolute top-0 left-0 w-full aspect-video md:aspect-auto md:inset-0 md:w-auto overflow-hidden transition-opacity duration-1000 pointer-events-none z-[1] "
                    <> opacity,
                  ),
                ],
                [
                  element.element(
                    "video",
                    [
                      attr("src", url),
                      attribute.property("muted", json.bool(True)),
                      attribute.property("autoplay", json.bool(True)),
                      attribute.property("playsInline", json.bool(True)),
                      attr("preload", "auto"),
                      attribute.class(
                        "w-full h-full object-cover md:absolute md:top-1/2 md:left-1/2 md:w-[100vw] md:h-[56.25vw] md:min-h-full md:min-w-[177.77vh] md:-translate-x-1/2 md:-translate-y-1/2 md:object-center",
                      ),
                      // Visibility: scroll + tab switch — pause when out of view
                      attr(
                        "onplaying",
                        "var v=this,p=v.parentElement.parentElement,a=p.querySelector('audio');if(a){a.currentTime=v.currentTime;a.play()}var h=v.closest('[style*=\"--hue\"]');if(h&&!h._vc){h._vc=1;var ck=function(){if(!v.isConnected){document.removeEventListener('scroll',ck);document.removeEventListener('visibilitychange',ck);return}if(document.hidden||v.ended){if(!v.paused)v.pause();return}var r=h.getBoundingClientRect();var vis=r.bottom>r.height*0.8&&r.top<window.innerHeight;if(vis){if(v.paused)v.play()}else{if(!v.paused)v.pause()}};document.addEventListener('scroll',ck,{passive:true});document.addEventListener('visibilitychange',ck)}",
                      ),
                      attr(
                        "onpause",
                        "var a=this.parentElement.parentElement.querySelector('audio');if(a)a.pause()",
                      ),
                      attr(
                        "ontimeupdate",
                        "var a=this.parentElement.parentElement.querySelector('audio');if(a&&Math.abs(a.currentTime-this.currentTime)>0.3)a.currentTime=this.currentTime",
                      ),
                      attr(
                        "onended",
                        "var a=this.parentElement.parentElement.querySelector('audio');if(a)a.pause()",
                      ),
                      event.on("playing", decode.success(VideoPlaying)),
                      event.on("ended", decode.success(VideoEnded)),
                    ],
                    [],
                  ),
                ],
              )
            }
          },
          // Audio track for trailer (separate stream, synced by video's onplaying)
          case hero.trailer_audio_url {
            "" -> element.none()
            audio_url ->
              element.element(
                "audio",
                [
                  attr("src", audio_url),
                  attribute.property("muted", json.bool(muted)),
                  attr("preload", "auto"),
                ],
                [],
              )
          },
          // Hulu-style video gradients (desktop only, visible when video playing)
          case video_playing {
            False -> element.none()
            True ->
              html.div(
                [
                  attribute.class(
                    "hidden md:block absolute inset-0 z-[2] pointer-events-none",
                  ),
                ],
                [
                  html.div(
                    [
                      attribute.class(
                        "w-full h-full absolute bg-linear-[104.16deg,#000,transparent_77.06%] -scale-y-100",
                      ),
                    ],
                    [],
                  ),
                  html.div(
                    [
                      attribute.class(
                        "w-full h-full absolute bg-linear-[180deg,#16181d,rgba(22,24,29,0)_50%] -scale-y-100",
                      ),
                    ],
                    [],
                  ),
                ],
              )
          },
          html.div(
            [
              attribute.class(
                "md:hidden absolute w-full h-full bg-linear-to-b from-transparent via-transparent via-5% to-black to-95%",
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
                "absolute py-16 px-[12.083333333333334vw] md:px-[7.8125vw] lg:px-[6.0546875vw] xl:px-[5.208333333333334vw] w-full h-full flex items-end z-[4]",
              ),
            ],
            [
              html.div([attribute.class("max-w-[var(--content-width)]")], [
                logo(hero),
                html.div(
                  [
                    attribute.class(
                      "grid transition-[grid-template-rows,opacity] duration-700 "
                      <> case video_playing {
                        True -> "grid-rows-[0fr] opacity-0"
                        False -> "grid-rows-[1fr] opacity-100"
                      },
                    ),
                  ],
                  [
                    html.div([attribute.class("overflow-hidden")], [
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
                          html.span(
                            [
                              attribute.class(
                                "font-semibold text-xs px-1.5 py-0.5 rounded border border-white/40 mr-2 uppercase tracking-wider",
                              ),
                            ],
                            [
                              html.text(case hero.media_type {
                                "movie" -> "Movie"
                                _ -> "Series"
                              }),
                            ],
                          ),
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
                    ]),
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
          // Mute/unmute button (bottom right, desktop only, visible when video playing)
          mute_button(hero, video_playing, muted),
        ],
      ),
    ],
  )
}

fn mute_button(hero: Hero, video_playing: Bool, muted: Bool) -> Element(Msg) {
  case hero.trailer_url {
    "" -> element.none()
    _ -> {
      let visibility = case video_playing {
        True -> "opacity-100"
        False -> "opacity-0 pointer-events-none"
      }
      html.button(
        [
          attribute.class(
            "hidden md:flex absolute bottom-[calc(4rem+4px)] right-[5.208333333333334vw] z-[5] items-center justify-center w-10 h-10 rounded-full border border-white/50 bg-black/30 backdrop-blur-sm cursor-pointer hover:bg-black/50 transition-all duration-500 "
            <> visibility,
          ),
          attr("aria-label", case muted {
            True -> "Unmute trailer for " <> hero.name
            False -> "Mute trailer for " <> hero.name
          }),
          event.on("click", decode.success(ToggleMute)),
        ],
        [
          case muted {
            True -> muted_icon()
            False -> unmuted_icon()
          },
        ],
      )
    }
  }
}

fn muted_icon() -> Element(Msg) {
  html.svg(
    [
      attr("viewBox", "0 0 24 24"),
      attr("width", "18"),
      attr("height", "18"),
      attr("fill", "white"),
      attr("xmlns", "http://www.w3.org/2000/svg"),
    ],
    [
      svg.g([attr("fill", "#FFF"), attr("fill-rule", "evenodd")], [
        svg.path([
          attr(
            "d",
            "M1.626 9.262H1a.75.75 0 00-.75.75v3.977c0 .416.333.75.75.75h4l.176.073 6.584 6.558.092.087c.573.517.898.351.898-.502v-4.641L1.626 9.262zm10.139-6.635L8.46 5.92l4.29 2.72V3.047c0-.888-.361-1.041-.985-.42z",
          ),
          attr("stroke", "#FFF"),
          attr("stroke-width", ".5"),
        ]),
        svg.path([
          attr(
            "d",
            "M17.458 19.029l1.835 1.168a20.86 20.86 0 01-2.846 1.697 1 1 0 11-.894-1.789 20.354 20.354 0 001.905-1.076zm-1.01-16.923C21.422 4.594 24 7.906 24 12a8.82 8.82 0 01-.748 3.604l-1.716-1.091c.31-.798.464-1.635.464-2.513 0-3.24-2.09-5.927-6.447-8.105a1 1 0 01.894-1.79zm.067 5.037C18.47 8.316 19.5 9.964 19.5 12c0 .395-.039.776-.116 1.142l-1.886-1.2-.004-.156c-.067-1.196-.706-2.147-2.008-2.928a1 1 0 011.029-1.715z",
          ),
          attr("fill-rule", "nonzero"),
          attr("opacity", ".5"),
        ]),
        svg.path([
          attr(
            "d",
            "M.463 5.844l22 14a1 1 0 001.074-1.688l-22-14A1 1 0 00.463 5.844z",
          ),
          attr("fill-rule", "nonzero"),
        ]),
      ]),
    ],
  )
}

fn unmuted_icon() -> Element(Msg) {
  html.svg(
    [
      attr("viewBox", "0 0 24 24"),
      attr("width", "18"),
      attr("height", "18"),
      attr("fill", "white"),
      attr("xmlns", "http://www.w3.org/2000/svg"),
    ],
    [
      svg.g([attr("fill", "#FFF"), attr("fill-rule", "evenodd")], [
        svg.path([
          attr(
            "d",
            "M11.765 2.627L5.176 9.012H1a.75.75 0 00-.75.75v3.977c0 .416.333.75.75.75h4.176l6.589 6.38c.624.622.985.469.985-.42V3.047c0-.888-.361-1.041-.985-.42z",
          ),
          attr("stroke", "#FFF"),
          attr("stroke-width", ".5"),
        ]),
        svg.path([
          attr(
            "d",
            "M16.448 2.106C21.422 4.594 24 7.906 24 12s-2.578 7.406-7.552 9.894a1 1 0 01-.894-1.79C19.91 17.928 22 15.242 22 12c0-3.24-2.09-5.927-6.447-8.105a1 1 0 01.894-1.79zm.067 5.037C18.47 8.316 19.5 9.964 19.5 12s-1.03 3.684-2.985 4.857a1 1 0 11-1.029-1.715C16.794 14.16 17.5 13.167 17.5 12s-.706-2.16-2.014-3.142a1 1 0 111.029-1.715z",
          ),
          attr("fill-rule", "nonzero"),
        ]),
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
      fade_img.view(
        "max-w-[var(--content-width)] max-h-[155px] w-[75%] md:w-full object-contain object-left-bottom",
        [
          attribute.src(img.url(hero.logo, "trim:10/")),
          attr(
            "onerror",
            "this.onerror=null;this.outerHTML='<h1 class=\" text-5xl font-bold max-w-[var(--content-width)] line-clamp-2 leading-tight\">"
              <> hero.name
              <> "</h1>'",
          ),
        ],
      )
  }
}

fn mobile_banner(hero: Hero) -> Element(Msg) {
  let src = case hero.poster {
    "" -> hero.banner
    url -> url
  }
  html.img(
    list.flatten([
      img.srcset(src, [480, 640, 828, 1080], "q:100/f:webp/"),
      [
        attribute.class(
          "md:hidden object-cover object-top w-full h-full absolute",
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
  )
}

fn generate_mobile_gradiants() -> Element(Msg) {
  html.div([attribute.class("md:hidden z-[3]")], [
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
  html.div([attribute.class("hidden md:block z-[3]")], [
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
