module TotpEnrolmentsHelper
  # The enrolment QR, drawn on the server as inline SVG.
  #
  # Inline rather than an <img> to a generated file: there is no JavaScript build step in this
  # application to add a QR library to, nothing for Propshaft to resolve, and no image written anywhere
  # that would then have to be cleaned up — a provisioning URI is a secret, and one that never becomes a
  # file cannot be left behind as one.
  #
  # html_safe rather than escaped, because the value is markup and nothing in it comes from the reader:
  # RQRCode is handed a URI it built itself from the account's own address and the issuer constant, and
  # what comes back is a path of black squares.
  #
  # The XML declaration is cut off rather than turned off.  `standalone: false` looks like the option for
  # it and is not: it drops the enclosing <svg> as well, leaving a bare <path> that draws nothing.
  #
  # @param [String] provisioning_uri
  # @return [String]
  def qr_code_svg(provisioning_uri)
    svg = RQRCode::QRCode.new(provisioning_uri)
                         .as_svg(use_path: true, viewbox: true, module_size: 6)

    svg.sub(/\A<\?xml[^>]*\?>/, "").html_safe
  end
end
