// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.23;

import { IERC165 } from "@openzeppelin/contracts/interfaces/IERC165.sol";

/// @title ILicenseTemplate
/// @notice This interface defines the methods for a License Template.
/// A License Template is responsible for defining a template of license terms that allow users to create
/// licenses based on the template terms.
/// The License Template contract is also responsible for registering, storing, verifying,
/// and displaying license terms registered with the License Template.
/// Anyone can implement a License Template and register it into the Story Protocol.
/// @dev The License Template should assign an unique ID to each license terms registered.
interface ILicenseTemplate is IERC165 {
    /// @notice Emitted when a new license terms is registered.
    /// @param licenseTermsId The ID of the license terms.
    /// @param licenseTemplate The address of the license template.
    /// @param licenseTerms The data of the license.
    event LicenseTermsRegistered(uint256 indexed licenseTermsId, address indexed licenseTemplate, bytes licenseTerms);

    /// @notice Returns the name of the license template.
    /// @return The name of the license template.
    function name() external view returns (string memory);

    /// @notice Converts the license terms to a JSON string.
    /// @param licenseTermsId The ID of the license terms.
    /// @return The JSON string of the license terms.
    function toJson(uint256 licenseTermsId) external view returns (string memory);

    /// @notice Returns the metadata URI of the license template.
    /// @return The metadata URI of the license template.
    function getMetadataURI() external view returns (string memory);

    /// @notice Returns the total number of registered license terms.
    /// @return The total number of registered license terms.
    function totalRegisteredLicenseTerms() external view returns (uint256);

    /// @notice Checks if a license terms exists.
    /// @param licenseTermsId The ID of the license terms.
    /// @return True if the license terms exists, false otherwise.
    function exists(uint256 licenseTermsId) external view returns (bool);

    /// @notice Checks if a license terms is transferable.
    /// @param licenseTermsId The ID of the license terms.
    /// @return True if the license terms is transferable, false otherwise.
    function isTransferable(uint256 licenseTermsId) external view returns (bool);

    /// @notice Returns the earliest expiration time among the given license terms.
    /// @param start The start time.
    /// @param licenseTermsIds The IDs of the license terms.
    /// @return The earliest expiration time.
    function getEarlierExpireTime(uint256 start, uint256[] calldata licenseTermsIds) external view returns (uint);

    /// @notice Returns the expiration time of a license terms.
    /// @param start The start time.
    /// @param licenseTermsId The ID of the license terms.
    /// @return The expiration time.
    function getExpireTime(uint256 start, uint256 licenseTermsId) external view returns (uint);

    /// @notice Returns the royalty policy of a license terms.
    /// @dev All License Templates should implement this method.
    /// The royalty policy is used to calculate royalties and pay minting license fee.
    /// Should return address(0) if the license template does not support a royalty policy or
    /// the license term does set RoyaltyPolicy.
    /// @param licenseTermsId The ID of the license terms.
    /// @return royaltyPolicy The address of the royalty policy specified for the license terms.
    /// @return royaltyData The data of the royalty policy.
    /// @return mintingLicenseFee The fee for minting a license.
    /// @return currencyToken The address of the ERC20 token, used for minting license fee and royalties.
    /// the currency token will used for pay for license token minting fee and royalties.
    function getRoyaltyPolicy(
        uint256 licenseTermsId
    )
        external
        view
        returns (address royaltyPolicy, bytes memory royaltyData, uint256 mintingLicenseFee, address currencyToken);

    /// @notice Verifies the minting of a license token.
    /// @dev the function will be called by the LicensingModule when minting a license token to
    /// verify the minting is whether allowed by the license terms.
    /// @param licenseTermsId The ID of the license terms.
    /// @param licensee The address of the licensee who will receive the license token.
    /// @param licensorIpId The IP ID of the licensor who attached the license terms minting the license token.
    /// @param amount The amount of licenses to mint.
    /// @return True if the minting is verified, false otherwise.
    function verifyMintLicenseToken(
        uint256 licenseTermsId,
        address licensee,
        address licensorIpId,
        uint256 amount
    ) external returns (bool);

    /// @notice Verifies the registration of a derivative.
    /// @dev This function is invoked by the LicensingModule during the registration of a derivative work
    //// to ensure compliance with the original intellectual property's licensing terms.
    /// It verifies whether the derivative's registration is permitted under those terms.
    /// @param derivativeIpId The IP ID of the derivative.
    /// @param originalIpId The IP ID of the original.
    /// @param licenseTermsId The ID of the license terms.
    /// @param licensee The address of the licensee.
    /// @return True if the registration is verified, false otherwise.
    function verifyRegisterDerivative(
        address derivativeIpId,
        address originalIpId,
        uint256 licenseTermsId,
        address licensee
    ) external returns (bool);

    /// @notice Verifies if the licenses are compatible.
    /// @dev This function is called by the LicensingModule to verify license compatibility
    /// when registering a derivative IP to multiple original IPs.
    /// It ensures that the licenses of all original IPs are compatible with each other during the registration process.
    /// @param licenseTermsIds The IDs of the license terms.
    /// @return True if the licenses are compatible, false otherwise.
    function verifyCompatibleLicenses(uint256[] calldata licenseTermsIds) external view returns (bool);

    /// @notice Verifies the registration of a derivative for all original IPs.
    /// @dev This function is called by the LicensingModule to verify licenses for registering a derivative IP
    /// to multiple original IPs.
    /// the function will verify the derivative for each original IP's license and
    /// also verify all licenses are compatible.
    /// @param derivativeIpId The IP ID of the derivative.
    /// @param originalIpId The IP IDs of the originals.
    /// @param licenseTermsIds The IDs of the license terms.
    /// @param derivativeIpOwner The address of the derivative IP owner.
    /// @return True if the registration is verified, false otherwise.
    function verifyRegisterDerivativeForAll(
        address derivativeIpId,
        address[] calldata originalIpId,
        uint256[] calldata licenseTermsIds,
        address derivativeIpOwner
    ) external returns (bool);
}